-- ============================================
-- KEY SYSTEM (DOSYADAN OKUR, POPUP GÖSTERİR)
-- ============================================

local KEY_URL = "https://testc.panelkuro.xyz/keylist.json"
local UPDATE_URL = "https://testc.panelkuro.xyz/update_device.php"
local KEY_FILE = "/storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/Xthrlen.txt"

-- Cihaz ID al
local function GetDeviceID()
    local id = ""
    pcall(function()
        local util = import("SystemUtil")
        if util and util.GetAndroidID then id = util:GetAndroidID() or "" end
    end)
    if id == "" then pcall(function() id = os.getenv("ANDROID_ID") or "" end) end
    if id == "" then
        pcall(function()
            local settings = import("GameUserSettings")
            if settings then id = tostring(settings:GetUniqueNetId()) end
        end)
    end
    return id or "UNKNOWN"
end

-- URL encode
local function urlEncode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w %-%_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

-- Dosyadan anahtar oku
local function LoadKey()
    local f = io.open(KEY_FILE, "r")
    if f then
        local key = f:read("*all"):gsub("%s+", "")
        f:close()
        return key ~= "" and key or nil
    end
    return nil
end

-- Dosyayı sil
local function DeleteKeyFile()
    os.remove(KEY_FILE)
end

-- JSON indir
local function DownloadJSON()
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local t = {}
    local ok, code = http.request{ url = KEY_URL, sink = ltn12.sink.table(t) }
    if ok and code == 200 then
        local s, data = pcall(json.decode, table.concat(t))
        if s then return data end
    end
end

-- Sunucuya cihaz kaydet
local function UpdateDeviceOnServer(key, device)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local body = "key=" .. urlEncode(key) .. "&device=" .. urlEncode(device)
    local resp = {}
    http.request{
        url = UPDATE_URL, method = "POST",
        source = ltn12.source.string(body),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-Length"] = tostring(#body)
        },
        sink = ltn12.sink.table(resp)
    }
    return table.concat(resp) == "OK"
end

-- Popup göster
local function ShowPopup(title, msg)
    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if Msg and Msg.Show then
            Msg.Show(1, title, msg, nil, nil, "TAMAM")
        end
    end)
end

-- Doğrulama
local function ValidateKey(key)
    local config = DownloadJSON()
    if not config then
        return false, "Sunucuya bağlanılamadı!"
    end

    local data = config[key]
    if not data then
        return false, "Anahtar geçersiz! Listede yok."
    end
    if not data.active then
        return false, "Anahtar engellenmiş!"
    end

    -- Süre
    local expiry = data.expiry
    if expiry then
        local y, m, d, h, min = expiry:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
        if y then
            local exp = os.time{year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=tonumber(h), min=tonumber(min), sec=0}
            if os.time() > exp then
                return false, "Süre dolmuş!\nBitiş: " .. expiry
            end
        end
    end

    -- Cihaz
    local dev = GetDeviceID()
    if data.device and data.device ~= "" and data.device ~= dev then
        return false, "Bu anahtar başka bir cihaza bağlı!"
    end

    -- İlk bağlama
    if not data.device or data.device == "" then
        if not UpdateDeviceOnServer(key, dev) then
            return false, "Cihaz kaydı yapılamadı!"
        end
    end

    return true, expiry
end

-- ==== BAŞLANGIÇ ====
local key = LoadKey()
if not key then
    ShowPopup("ANAHTAR YOK", "Lutfen Xthrlen.txt dosyasina\nanahtarinizi yazin ve oyuna tekrar girin.\n\nYol:\n" .. KEY_FILE)
    return
end

local ok, expiry = ValidateKey(key)
if ok then
    _G.VALID_KEY_TYPE = "VIP"
    _G.USER_EXPIRY_TIME = expiry
    ShowPopup("BASARILI", "Anahtar dogrulandi!\nVIP aktif.\nBitis: " .. (expiry or "Suresiz"))
else
    DeleteKeyFile()
    ShowPopup("HATA", expiry .. "\n\nAnahtar dosyasi silindi.\nYeni anahtari tekrar Xthrlen.txt dosyasina yazip oyunu yeniden baslatin.")
end
