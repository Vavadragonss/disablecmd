-- enable_cmd.lua
-- Attempt to re-enable Command Prompt by removing or resetting DisableCMD registry values.
-- Works on Windows. Will export backups of the keys it touches.
-- Requires admin for HKLM changes. Use only on machines you own/administer.

local function is_windows()
  return package.config:sub(1,1) == "\\"
end

if not is_windows() then
  print("This script only runs on Windows.")
  os.exit(1)
end

local function run(cmd)
  -- print the command for transparency, then run it
  print("> " .. cmd)
  local ok = os.execute(cmd)
  if ok == 0 or ok == true then
    return true
  else
    return false, ok
  end
end

local function query_disablecmd(root)
  local key = root .. "\\Software\\Policies\\Microsoft\\Windows\\System"
  local cmd = string.format('reg query "%s" /v DisableCMD 2>&1', key)
  local f = io.popen(cmd)
  local out = f:read("*a")
  f:close()
  if out:match("DisableCMD") then
    -- try to parse a hex/decimal value like 0x0 or 0x1 or decimal at end of line
    local v = out:match("0x%x+")
    if v then return v end
    local dec = out:match("%s(%d+)%s*$")
    if dec then return dec end
    return "present"
  end
  return nil
end

local function backup_key(root, destfile)
  local key = root .. "\\Software\\Policies\\Microsoft\\Windows\\System"
  local cmd = string.format('reg export "%s" "%s" /y 2>nul', key, destfile)
  return run(cmd)
end

local function remove_disablecmd(root)
  local key = root .. "\\Software\\Policies\\Microsoft\\Windows\\System"
  -- Delete the value if present
  local delcmd = string.format('reg delete "%s" /v DisableCMD /f', key)
  return run(delcmd)
end

local function ensure_key_exists(root)
  local key = root .. "\\Software\\Policies\\Microsoft\\Windows\\System"
  local addcmd = string.format('reg add "%s" /f', key)
  return run(addcmd)
end

local function set_disablecmd_zero(root)
  local key = root .. "\\Software\\Policies\\Microsoft\\Windows\\System"
  local addcmd = string.format('reg add "%s" /v DisableCMD /t REG_DWORD /d 0 /f', key)
  return run(addcmd)
end

print("=== Attempting to re-enable Command Prompt (cmd.exe) ===")
print("This will try HKCU (current user) first, then HKLM (all users).")
print("Backups of touched keys will be saved next to this script if possible.\n")

local roots = {
  {name="HKCU", root='HKCU'},
  {name="HKLM", root='HKLM'}
}

for _, r in ipairs(roots) do
  io.write(string.format("--- Checking %s ... ", r.name)); io.flush()
  local q = query_disablecmd(r.root)
  if not q then
    print("no DisableCMD value found.")
  else
    print("DisableCMD present (" .. tostring(q) .. ").")
    local bakfile = string.format("registry_backup_%s_System.reg", r.name)
    if backup_key(r.root, bakfile) then
      print("  backed up to " .. bakfile)
    else
      print("  could not export backup (maybe insufficient privileges).")
    end

    -- Prefer removing the value; if that fails try setting to 0
    local ok, err = remove_disablecmd(r.root)
    if ok then
      print("  removed DisableCMD from " .. r.name .. " (or it didn't exist).")
    else
      print("  removal failed or returned " .. tostring(err) .. " — attempting to set to 0.")
      ensure_key_exists(r.root) -- create key if needed
      if set_disablecmd_zero(r.root) then
        print("  set DisableCMD = 0 in " .. r.name)
      else
        print("  failed to set DisableCMD = 0 in " .. r.name .. ". You may need admin rights.")
      end
    end
  end
end

print("\nNotes:")
print("- If the value is enforced by Group Policy (domain-level), this will be reverted by the policy.")
print("- To test now, press Win+R, type: cmd  and Enter, or run: taskmgr /run cmd  (or simply run 'cmd').")
print("- If things still don't work, try restarting or sign out / sign in.")
print("\nFinished.")
