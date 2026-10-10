OSC_Logger = {}

function OSC_Logger.Log(message)
    print("[OSC] " .. tostring(message))
end

function OSC_Logger.Error(message)
    print("[OSC] ERROR: " .. tostring(message))
end
