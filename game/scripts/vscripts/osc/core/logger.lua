OSC_Logger = OSC_Logger or {}

function OSC_Logger.Log(message)
    print("[OSC] " .. tostring(message))
end

function OSC_Logger.Error(message)
    print("[OSC] ERROR: " .. tostring(message))
end
