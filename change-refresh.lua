--[[
    This script uses WindowsDisplayManager to change the refresh rate of the display that the mpv window is currently open in

    If the display does not support the specified resolution or refresh rate it will silently fail
    If the video refresh rate does not match any on the whitelist it will pick the next highest.
    If the video fps is higher tha any on the whitelist it will pick the highest available
    The whitelist is specified via the script-opt 'rates'. Valid rates are separated via semicolons, do not include spaces and list in asceding order.
        Example:    script-opts=changerefresh-rates="23;24;30;60"

    You can also set a custom display rate for individual video rates using a hyphen:
        Example:    script-opts=changerefresh-rates="23;24;25-50;30;60"
    This will change the display to 23, 24, and 30 fps when playing videos in those same rates, but will change the display to 50 fps when
    playing videos in 25 Hz

    The script will keep track of the original refresh rate of the monitor and revert when mpv exits.

    Note that if the mpv window is lying across multiple displays it may not save the original refresh rate of the correct display

    See below for the full options list, don't change the defaults manually, use script opts.
]]--

msg = require 'mp.msg'
utils = require 'mp.utils'
require 'mp.options'

--options available through --script-opts=changerefresh-[option]=value
--all of these options can be changed at runtime using profiles, the script will automatically update
local options = {
    --list of valid refresh rates, separated by semicolon, listed in ascending order
    --by adding a hyphen after a number you can set a custom display rate for that specific video rate:
    --  "23;24;25-50;60"  Will set the display to 50fps for 25fps videos
    --this whitelist also applies when attempting to revert the display, so include that rate in the list
    --WindowsDisplayManager only seems to work with integers, DO NOT use the full refresh rate, i.e. 23.976
    -- rates = "23;24;25;29;30;50;59;60",
    rates = "23-48;24-48;25-50;29-60;30-60;50;59-60;60",

    --duration (in seconds) of the pause when changing display modes
    --set to zero to disable video pausing
    pause = 2,

    --set whether to use the estimated fps or the container fps
    --see https://mpv.io/manual/master/#command-interface-container-fps for details
    estimated_fps = false,

    --set whether to output status messages to the osd
    osd_output = true
}

local var = {
    dnumber = "",

    original_fps = 0,
    new_fps = 0,

    beenReverted = true,
    rateList = {},
    rates = {}
}

--is run whenever a change in script-opts is detected
function updateOptions(changes)
    msg.info('updating options')
    msg.info(utils.to_string(changes))

    --only runs the heavy commands if the rates string has been changed
    if changes == nil or changes.rates then
        msg.info('rates whitelist has changed')

        checkRatesString()
        updateTable()
    end
end
read_options(options, 'changerefresh', updateOptions)

--checks if the rates string contains any invalid characters
function checkRatesString()
    local str = options.rates

    str = str:gsub(";", '')
    str = str:gsub("%-", '')

    if str:match("%D") then
        msg.error('Rates whitelist contains invalid characters, can only contain numbers, semicolons and hyphens. Be prepared for the script to crash')
    end
end

--creates an array of valid video rates and a map of display rates to switch to
function updateTable()
    var.rates = {}
    var.rateList = {}

    msg.info("updating tables of valid rates")
    for rate in string.gmatch(options.rates, "[^;]+") do
        msg.info("found option: " .. rate)
        if rate:match("-") then
            msg.info("contains hyphen, extracting custom rates")

            local originalRate = rate:gsub("-.*$", "")
            msg.info("-originalRate = " .. originalRate)

            local newRate = rate:gsub(".*-", "")
            msg.info("-customRate = " .. newRate)

            originalRate = tonumber(originalRate)
            newRate = tonumber(newRate)

            --tests for nil values caused by missing rates on either side of hyphens
            if originalRate == nil and newRate == nil then
                msg.info('-no rates found, ignoring')
                goto loopend
            end

            if originalRate == nil then
                msg.warn("missing rate before hyphen in whitelist, ignoring option")
                goto loopend
            end
            if newRate == nil then
                msg.warn("missing rate after hyphen in whitelist for option: " .. rate)
                msg.warn("ignoring and setting " .. rate .. " to " .. originalRate)
                newRate = originalRate
            end
            var.rates[originalRate] = newRate
            rate = originalRate
        else
            rate = tonumber(rate)
            var.rates[rate] = rate
        end
        table.insert(var.rateList, rate)

        ::loopend::
    end

    if #var.rateList < 1 then
        msg.warn('rate list empty, will not be able to change refresh rate')
    end
end

--prints osd messages if the option is enabled
function osdMessage(string)
    if options.osd_output then
        mp.osd_message(string)
    end
end

--Finds the name of the display mpv is currently running on
--the names are in the form \\.\DISPLAY# starting from 1, while the integers start from 0
function getDisplayDetails()
    local name = mp.get_property_native('display-names')

    --the display-fps property always refers to the display with the lowest refresh rate
    --there is no way to test which display this is, so reverting the refresh when mpv is on multiple monitors is unpredictable
    --however, by default I'm just selecting whatever the first monitor in the list is
    if #name > 1 then
        msg.warn('mpv window is on multiple displays, script may revert to wrong display rate')
    end

    name = name[1]
    msg.info('display name = ' .. name)

    --the last character in the name will always be the display number
    --we extract the integer and subtract by 1, as display index starts from 0
    local number = string.sub(name, -1)
    number = tonumber(number)
    number = tostring(number - 1)

    -- if ((var.beenReverted == false) and (var.dnumber ~= number)) then
    --     msg.info('changing new display, reverting old one first')
    --     revertRefresh()
    -- end

    var.dnumber = number
    var.beenReverted = false
end

--picks which whitelisted rate to switch the monitor to
function findValidRate(rate)
    msg.info('searching for closest valid rate to ' .. rate)

    --if the rate already exists in the table then the function just returns that
    if var.rates[rate] ~= nil then
        msg.info(rate .. ' already in list, returning matching rate: ' .. var.rates[rate])
        return var.rates[rate]
    end

    local closestRate
    rate = tonumber(rate)

    --picks either the same fps in the whitelist, or the next highest
    --if none of the whitelisted rates are higher, then it uses the highest
    for i = 1, #var.rateList, 1 do
        closestRate = var.rateList[i]
        msg.info('comparing ' .. rate .. ' to ' .. closestRate)
        if (closestRate >= rate) then
            break
        end
    end

    if closestRate == nil then
        closestRate = 0
    end
    msg.info('closest rate is ' .. closestRate .. ', saving...')

    --saves the rate to reduce repeated searches
    var.rates[rate] = var.rates[closestRate]

    return closestRate
end

--executes commands to switch monior to video refreshrate
function matchVideo()
    --saves either the estimated or specified fps of the video
    if (options.estimated_fps == true) then
        var.new_fps = mp.get_property_number('estimated-vf-fps', 0)
    else
        var.new_fps = mp.get_property_number('container-fps', 0)
    end

    --Floor is used because 23fps video has an actual framerate of ~23.9, this occurs across many video rates
    var.new_fps = math.floor(var.new_fps)

    --picks which whitelisted rate to switch the monitor to based on the video rate
    var.new_fps = findValidRate(var.new_fps)

    --if beenReverted=true, then the current display settings may not be saved
    if (var.beenReverted == true) and (var.new_fps ~= var.original_fps) then
        var.original_fps = math.floor(mp.get_property_number('display-fps'))
        msg.info('saving original fps: ' .. var.original_fps)
    end
end


function split(str)
    local lines = {}
    for s in str:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

function wdmCommand(command)
    local process = mp.command_native({
        name = 'subprocess',
        playback_only = false,
        capture_stdout = true,
        args = {
            "powershell",
            "-command",
            'Import-Module WindowsDisplayManager;',
            '$d = (WindowsDisplayManager\\GetEnabledDisplays | ',
            'Where-Object -FilterScript {',
            '$_.ID.StartsWith(\'' .. var.dnumber ..'-\')',
            '})[0];',
            command
        }
    })

    if (process.status < 0) then
        local error = process.error_string
        msg.warn(utils.to_string(process))
        msg.warn(error)
        msg.error('Error sending command')
    end

    if process.stdout:match('^WARNING') then
        msg.warn(process.stdout)
    end

    return process.stdout
end

function updateDisplay(_, primaries)
    if primaries == nil then
        return
    end

    local time = mp.get_time()
    while time + 0.75 > mp.get_time() do end

    local playing = mp.get_property_bool("pause") ~= true

    if playing then
        msg.info('pausing')
        osdMessage('Loading new display settings')
        mp.set_property_bool("pause", true)
    end

    getDisplayDetails()

    -- get the current display dimensions
    local res = wdmCommand(
        '$d.Resolution.Width; $d.Resolution.Height; $d.Resolution.RefreshRate; $d.HdrInfo.HdrSupported; $d.HdrInfo.HdrEnabled'
    )
    local width, height, refresh, hdrSupported, hdrEnabled = unpack(split(res))

    matchVideo()

    local enableHDR = hdrEnabled == 'True'
    if primaries == 'bt.2020' then
        if hdrSupported == 'True' and hdrEnabled == 'False' then
            enableHDR = true
        end
    else
        if hdrEnabled == 'True' then
            enableHDR = false
        end
    end

    osdMessage(string.format('Setting display to %d Hz, HDR %s', var.new_fps, enableHDR and 'on' or 'off'))
    wdmCommand(string.format(
        '$d.SetResolution(%d, %d, %d); %s',
        width, height, var.new_fps,
        enableHDR and '$d.EnableHdr()' or '$d.DisableHdr()'
    ))

    if playing then
        mp.add_timeout(options.pause, function()
            mp.set_property_bool("pause", false)
        end)
    end

    local done = false
    function onEnd()
        if done then
            return
        end
        done = true
        wdmCommand(string.format(
            '$d.SetResolution(%d, %d, %d); %s',
            width, height, refresh,
            hdrEnabled == 'True' and '$d.EnableHdr()' or '$d.DisableHdr()'
        ))
    end

    mp.register_event('end-file', onEnd)
    mp.register_event('shutdown', onEnd)
    mp.register_event('stop', onEnd)

    print(mp.get_property('width'), 'x', mp.get_property('height'), primaries)
end

updateOptions()

mp.observe_property('video-params/primaries', 'string', updateDisplay)
