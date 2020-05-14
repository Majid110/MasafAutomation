include("karaskel.lua")

local tr = aegisub.gettext
local utf8 = require "utf8"
--local inspect = require "inspect"

add_background_script_name = tr "Masaf/Add Backgrounds"
split_script_name = tr "Masaf/Split line"
split_at_index_script_name = tr "Masaf/Split line at Index"
rtl_correction_script_name = tr "Masaf/Rtl Correction - All line"
rtl_correction_selected_line_script_name = tr "Masaf/Rtl Correction - Selected"
undo_rtl_correction_script_name = tr "Masaf/Undo Rtl Correction - Selected"
show_rtl_editor_script_name = tr "Masaf/Show Rtl Editor"
unify_background_lines_script_name = tr "Masaf/Unify Background lines"
add_code_to_selected_lines_script_name = tr "Masaf/Add Code to Selected lines"
remove_line_break_script_name = tr "Masaf/Remove line Breaks"
import_text_to_selected_lines = tr "Masaf/Import text to selected Lines"
select_playing_line = tr "Masaf/Select playing line"
make_next_line_continuous = tr "Masaf/Make next line continuous"
shift_start_line_forward = tr "Masaf/Shift start line forward"
shift_start_line_backward = tr "Masaf/Shift start line backward"
shift_end_line_forward = tr "Masaf/Shift end line forward"
shift_end_line_backward = tr "Masaf/Shift end line backward"
move_last_text_part = tr "Masaf/Move last text part"
move_first_part_of_next = tr "Masaf/Move first part of next"
move_last_word = tr "Masaf/Move last word"
move_first_word_of_next = tr "Masaf/Move first word of next"
remove_position_tags = tr "Masaf/Remove Position tags"
display_sum_of_times = tr "Masaf/Display sum of times"
generate_srt_like_text = tr "Masaf/Generate SRT like text"

script_description = tr "Some Aegisub automation scripts specially designed for Right-To-Left language subtitles"
script_author = "Majid Shamkhani"
script_version = "1.13.0"

-- <<<<<<<<<<<<<<<<<<<<<<<<< Main Methods >>>>>>>>>>>>>>>>>>>>>>>>>

-- ------------------------- AddBackground ---------------------

bgPattern = [[{\p1\pos%(.-%)}m %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+]]
posPattern = "^{\\pos%(.-%)}"
bgPosPattern = "^{\\p1\\pos%(.-%)}"

rleChar = utf8.char(0x202B)
pdfChar = utf8.char(0x202C)

function AddBackground(subs)
	if not videoLoaded() then
		return
	end

	local meta, styles = karaskel.collect_head(subs)
	-- start processing lines
	local i, n = 0, #subs
	n = subs.n
	local periorEndTime = ""
	local groupBackgroundIndex = -1
	local groupCount = 0
	local lastLineCount = 0

	local bgShape, doExit = getBackgroundLine(subs, styles)

	-- Missing background shape
	-- Adding new shape line and exit
	if doExit then
		return
	end

	-- Comment background line	
	bgShape.comment = true
	subs[bgShape.i] = bgShape

	local positionTag = getPositionTag(bgShape.text)

	local secondForContinuousBackground =
		getNumberFromUser("\r\n Enter maximum second to make background continious: \r\n", 3)
	if secondForContinuousBackground == 0 then
		return
	end

	local textStyle = nil
	while i < n do
		i = i + 1

		aegisub.progress.task("Processing line " .. i .. "/" .. n)
		aegisub.progress.set(i / n * 100)

		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and shouldAddBackground(l) then
			-- remove already added background line
			if bgShape ~= nil and i ~= bgShape.i and isBackgroundLine(l) then
				subs.delete(i)
				i = i - 1
				n = n - 1
				goto continue
			end

			-- Set text style align to 5 once.
			if textStyle == nil then
				textStyle = changeStyleAlignToFive(subs, styles, l)
			end
			
			if not string.find(l.text, "\\fixedpos") then
				l.text = addPositionTag(l.text, positionTag)
			end
			subs[i] = l

			local startTimeEqualsPeriorEndTime = isStartTimeEqualsPeriorEndTime(l, periorEndTime, secondForContinuousBackground)

			if not startTimeEqualsPeriorEndTime then
				l.i = i
				l.comment = false
				local bgLine = generateBackground(l, bgShape)
				if groupBackgroundIndex ~= -1 and groupCount > 0 then
					setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime)
					groupCount = 0
				end
				subs.insert(i, bgLine)
				groupBackgroundIndex = i
				i = i + 1
				n = n + 1
			else
				groupCount = groupCount + 1
			end

			periorEndTime = l.end_time
			lastLineCount = calcLineCount(l, styles)

			::continue::
		end
	end

	if groupCount > 0 then
		setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime)
	end

	aegisub.set_undo_point(add_background_script_name)
end

------------------------------ Split Line -----------------------------

local SplitChars = {"||", "\\N", "%.", ",", "،", ";", "%?", "؟", "!", ":", "؛"}

function Split(subs, selected)
	if #selected > 1 then
		return
	end
	local index = selected[1]
	line = subs[index]
	text = line.text

	line2 = table.copy(line)

	-- Finding manual splittnig symbol -> ||
	local s, e = utf8.find(text, SplitChars[1])
	if s then
		line.text = utf8.sub(text, 1, s - 1)
		line2.text = utf8.sub(text, e + 1, utf8.len(text))
		line.text = applyRtlCorrection(trim(line.text))
		line2.text = applyRtlCorrection(trim(line2.text))
		changeLineTimeAterSplit(text, line, line2)
		subs[index] = line
		subs.insert(index + 1, line2)
		goto continue
	end

	s, e, idx = getFirstChar(text, SplitChars)
	if e > 0 then
		-- Remove split char from end of text
		if idx <= 2 then
			line.text = utf8.sub(text, 1, s - 1)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		else
			line.text = utf8.sub(text, 1, e)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		end
		changeLineTimeAterSplit(text, line, line2)
		line.text = applyRtlCorrection(trim(line.text))
		line2.text = applyRtlCorrection(trim(line2.text))
		subs[index] = line
		subs.insert(index + 1, line2)
	end

	::continue::

	aegisub.set_undo_point(split_script_name)
	return selected
end

-- -------------------------SplitAtIndex ---------------------

function SplitAtIndex(subs, selected)
	if #selected > 1 then
		return
	end
	local line = subs[selected[1]]

	text = line.text

	line2 = table.copy(line)

	local idx = getNumberFromUser("\r\n Enter index of character that you want to split line on that character: \r\n", 2)

	if idx == 0 then
		return
	end

	local s, e, idx = getCharAtIndex(text, idx)
	if s then
		-- Remove split char from end of text
		if idx <= 2 then
			line.text = utf8.sub(text, 1, s - 1)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		else
			line.text = utf8.sub(text, 1, e)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		end
		changeLineTimeAterSplit(text, line, line2)
		line.text = applyRtlCorrection(line.text)
		line2.text = applyRtlCorrection(line2.text)
		subs[selected[1]] = line
		subs.insert(selected[1] + 1, line2)
	end

	aegisub.set_undo_point(split_at_index_script_name)
	return selected
end

--------------------------- RtlCorrection ---------------------

local SpecialChars = [[%.,،%?؟«»!%-:]]
local PunctuationMarks = [[%.,،%?؟:؛!;]]
local StartingBracketChars = [[%({%[<«“]]
local EndingsBracketChars = [[%)}%]>»”]]
local CodePattern = "({.-})"

function RtlCorrection(subs)
	-- start processing lines
	local i, n = 0
	n = subs.n

	while i < n do
		i = i + 1
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment then
			if not isBackgroundLine(l) then
				local parts = getSubtitleTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					t = applyRtlCorrection(t)
					text = text .. t
				end
				l.text = text
				subs[i] = l
			end
		end
	end

	aegisub.set_undo_point(rtl_correction_script_name)
end

------------------------- Rtl Corrector Selected Line -----------------------

function RtlCorrectorSelectedLine(subs, selected)
	if #selected > 1 then
		return
	end

	local line = subs[selected[1]]

	-- start processing lines

	if not isBackgroundLine(line) then
		local parts = getSubtitleTextParts(line.text)
		local text = ""
		for k = 1, #parts do
			local t = parts[k]
			t = applyRtlCorrection(t)
			text = text .. t
		end
		line.text = text
		subs[selected[1]] = line
	end

	aegisub.set_undo_point(rtl_correction_selected_line_script_name)
end

------------------------------ Undo Rtl Correction ----------------------------

function UndoRtlCorrection(subs, selected)
	if #selected > 1 then
		return
	end
	local line = subs[selected[1]]
	line.text = removeRtlChars(line.text)
	subs[selected[1]] = line

	aegisub.set_undo_point(undo_rtl_correction_script_name)
end

------------------------------ Show Rtl Editor ---------------------------------

function ShowRtlEditor(subs, selected)
	if #selected > 1 then
		return
	end
	local line = subs[selected[1]]
	local result, text = openEditor(line.text)

	if not result then
		return
	end
	-- Replace line break with \N
	text = utf8.gsub(text, "\n", "\\N")
	line.text = text
	subs[selected[1]] = line

	aegisub.set_undo_point(show_rtl_editor_script_name)
end

--------------------------- Unify Background lines ------------------------------

function UnifyBackgroundLines(subs, selected)
	local firstLine, firstLineIdx = getFirstSubtitleLine(subs)
	if not isBackgroundLine(firstLine) then
		return
	end
	-- start processing lines
	local i, n = 0
	n = subs.n
	local lastBackgroundIdx = firstLineIdx

	while i < n do
		i = i + 1
		local l = subs[i]

		-- Prevent moving first line (Background shape)
		if l.class == "dialogue" and l.effect == "" and i ~= firstLineIdx then
			if isBackgroundLine(l) then
				lastBackgroundIdx = lastBackgroundIdx + 1
				subs.insert(lastBackgroundIdx, l)
				i = i + 1
				subs.delete(i)
			end
		end
	end

	aegisub.set_undo_point(unify_background_lines_script_name)
end

--------------------------- Add Code To Selected Lines ------------------------------
function AddCodeToSelectedLines(subs, selected)
	local code = getTextFromUser()
	if code == nil then
		return
	end
	for i = 1, #selected, 1 do
		local line = subs[selected[i]]
		line.text = code .. line.text
		subs[selected[i]] = line
	end
	aegisub.set_undo_point(add_code_to_selected_lines_script_name)
end

--------------------------- Remove line Breaks ------------------------------
function RemoveLineBreaks(subs, selected)
	if #selected > 1 then
		return
	end
	local line = subs[selected[1]]
	line.text = utf8.gsub(line.text, "\\N", " ")
	subs[selected[1]] = line

	aegisub.set_undo_point(remove_line_break_script_name)
end

---------------------- Import Text to selected lines -------------------------
function ImportTextToSelectedLines(subs, selected)
	if #selected == 0 then
		return
	end
	local result, text = openEditor("")

	if not result then
		return
	end
	local texts = text:split("\n")
	for i = 1, #selected, 1 do
		if i > table.getn(texts) then
			return
		end
		local line = subs[selected[i]]
		line.text = texts[i]
		subs[selected[i]] = line
	end

	aegisub.set_undo_point(import_text_to_selected_lines)
end

---------------------- Select playing line -------------------------
function SelectPlayingLine(subs, selected)
	local vframe = aegisub.project_properties().video_position
	fr2ms = aegisub.ms_from_frame

	local j = #selected
	if j < 1 or j == #subs then
		j = 1
	end
	for i = j, #subs do
		local line = subs[i]
		if line.class == "dialogue" and line.start_time >= fr2ms(vframe) then
			selected = {i - 1}
			return selected
		end
	end
	if j > 1 then
		for i = 1, j do
			local line = subs[i]
			if line.class == "dialogue" and line.start_time >= fr2ms(vframe) then
				selected = {i - 1}
				return selected
			end
		end
	end
end

---------------------- Make next line continuous -------------------------
function MakeNextLineContinuous(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	if index == subs.n then
		return
	end
	local line = subs[index]
	local nextLine = subs[index + 1]
	nextLine.start_time = line.end_time
	if nextLine.end_time == 0 then
		nextLine.end_time = line.end_time + (utf8.len(nextLine.text) * 100)
	end
	subs[index + 1] = nextLine
	selected = {index + 1}
	aegisub.set_undo_point(make_next_line_continuous)
	return selected
end

---------------------- Start/End line shifter -------------------------
function ShiftStartLineForward(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	local line = subs[index]
	line.start_time = line.start_time + 100
	subs[index] = line
	aegisub.set_undo_point(shift_start_line_forward)
end

function ShiftStartLineBackward(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	local line = subs[index]
	line.start_time = line.start_time - 100
	subs[index] = line
	aegisub.set_undo_point(shift_start_line_backward)
end

function ShiftEndLineForward(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	local line = subs[index]
	line.end_time = line.end_time + 100
	subs[index] = line
	aegisub.set_undo_point(shift_end_line_forward)
end

function ShiftEndLineBackward(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	local line = subs[index]
	line.end_time = line.end_time - 100
	subs[index] = line
	aegisub.set_undo_point(shift_end_line_backward)
end

---------------------- Move part of lines -------------------------
function MoveLastTextPart(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	if index == subs.n then
		return
	end
	local line = subs[index]
	local nextLine = subs[index + 1]
	local text = line.text
	local oldLine = table.copy(line)
	local parts = getTextSplitCharsParts(text)
	if #parts == 0 then
		return
	end
	local textParts = getTextPartsBySplitCharIndexes(parts, text)

	text = ""
	for i = 1, #textParts - 1, 1 do
		text = text .. textParts[i] .. " "
	end

	line.text = trim(text)
	nextLine.text = trim(textParts[#textParts]) .. " " .. nextLine.text
	line.text = applyRtlCorrection(line.text)
	nextLine.text = applyRtlCorrection(nextLine.text)
	changeLineTimeAterMove(oldLine, line, nextLine)
	subs[index] = line
	subs[index + 1] = nextLine

	aegisub.set_undo_point(move_last_text_part)
end

function MoveFirstPartOfNext(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	if index == subs.n then
		return
	end
	local line = subs[index]
	local nextLine = subs[index + 1]
	local text = nextLine.text
	local oldLine = table.copy(line)
	local parts = getTextSplitCharsParts(text)
	if #parts == 0 then
		return
	end
	local textParts = getTextPartsBySplitCharIndexes(parts, text)

	text = ""
	for i = 2, #textParts, 1 do
		text = text .. textParts[i] .. " "
	end

	nextLine.text = trim(text)
	line.text = line.text .. " " .. trim(textParts[1])
	line.text = applyRtlCorrection(line.text)
	nextLine.text = applyRtlCorrection(nextLine.text)
	changeLineTimeAterMove(oldLine, line, nextLine)
	subs[index] = line
	subs[index + 1] = nextLine

	aegisub.set_undo_point(move_first_part_of_next)
end

---------------------- Move words -------------------------
function MoveLastWord(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	if index == subs.n then
		return
	end
	local line = subs[index]
	local nextLine = subs[index + 1]
	local text = trim(line.text)
	local oldLine = table.copy(line)
	local lastWord = getLastWord(text)
	if lastWord == nil then
		return
	end

	local textLen = utf8.len(text)
	line.text = utf8.sub(text, 1, textLen - utf8.len(lastWord) - 1)
	nextLine.text = lastWord .. " " .. nextLine.text
	line.text = applyRtlCorrection(trim(line.text))
	nextLine.text = applyRtlCorrection(trim(nextLine.text))
	changeLineTimeAterMove(oldLine, line, nextLine)
	subs[index] = line
	subs[index + 1] = nextLine

	aegisub.set_undo_point(move_last_word)
end

function MoveFirstWordOfNext(subs, selected)
	if #selected == 0 or #selected > 1 then
		return
	end
	local index = selected[1]
	if index == subs.n then
		return
	end
	local line = subs[index]
	local nextLine = subs[index + 1]
	local text = trim(nextLine.text)
	local oldLine = table.copy(line)
	local firstWord = getFirstWord(text)
	if firstWord == nil then
		return
	end

	line.text = line.text .. " " .. firstWord
	nextLine.text = utf8.sub(text, utf8.len(firstWord) + 1, utf8.len(text))
	line.text = applyRtlCorrection(trim(line.text))
	nextLine.text = applyRtlCorrection(trim(nextLine.text))
	changeLineTimeAterMove(oldLine, line, nextLine)
	subs[index] = line
	subs[index + 1] = nextLine

	aegisub.set_undo_point(move_first_word_of_next)
end

---------------------- Remove Position Tags -------------------------
function RemovePositionTags(subs)
	for i = 1, #subs do
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and (not l.comment) and (not isBackgroundLine(l)) then
			l.text = removePosTag(l.text)
			subs[i] = l
		end
	end
	aegisub.set_undo_point(remove_position_tags)
end

---------------------- Display sum of times -------------------------
function DisplaySumOfTimes(subs)
	local sum = 0
	for i = 1, #subs do
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and (not l.comment) and (not isBackgroundLine(l)) then
			sum = sum + (l.end_time - l.start_time)
		end
	end

	local minutes = math.ceil(sum / 1000 / 60)
	local msg = "Total minutes  = " .. tostring(minutes)
	msg = msg .. "\nTotal time = " .. secondsToClock(sum / 1000)
	showMessage(msg)
end

---------------------- Generate SRT Like Text -------------------------
function GenerateSrtLikeText(subs)
	local sum = 0
	local srtText = ""
	local lineNumber = 0
	for i = 1, #subs do
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" then
			lineNumber = lineNumber + 1
			if (not l.comment) and (not isBackgroundLine(l)) then
				srtText = srtText .. lineNumber .. "\n"
				srtText = srtText .. secondsToClock(l.start_time / 1000) .. "  -->  " .. secondsToClock(l.end_time / 1000) .. "\n"
				srtText = srtText .. replaceLineBreak(cleanTags(l.text)) .. "\n"
				srtText = srtText .. "\n"
			end
		end
	end
	openEditor(srtText)
end
------------------------- End of Main Methods -------------------

-- <<<<<<<<<<<<<<<<<<<<< Related Methods >>>>>>>>>>>>>>>>>>>>>>>>

---------------------- AddBackground Methods ------------------

function generateBackground(line, bgShape)
	local bgLine = table.copy(line)
	bgLine.text = bgShape.text
	bgLine.style = bgShape.style
	return bgLine
end

function calcLineCount(line, styles)
	local text = line.text
	local videoWidth = getVideoWidth()
	local lineCount = 0
	if text:match([[\N]]) ~= nil then
		local l = table.copy(line)
		local lineParts = text:split([[\N]])
		for i, t in ipairs(lineParts) do
			l.text = t
			lineCount = lineCount + getNoneBreakedLineCount(l, videoWidth, styles)
		end
	else
		lineCount = getNoneBreakedLineCount(line, videoWidth, styles)
	end
	return lineCount
end

function getTextWidth(line, styles)
	local cleanedText = cleanTags(line.text)
	local w = aegisub.text_extents(styles[line.style], cleanedText)
	return w
end

function getTextHeight(styles, line)
	local cleanedText = cleanTags(line.text)
	local w, h = aegisub.text_extents(styles[line.style], cleanedText)
	return h
end

function getNoneBreakedLineCount(line, videoWidth, styles)
	local stringWidth = getTextWidth(line, styles)
	local margin = line.margin_l + line.margin_r
	local drawableWidth = videoWidth - margin
	return math.ceil(stringWidth / drawableWidth)
end

function getVideoWidth()
	local xres, yres = aegisub.video_size()
	return xres
end

function getVideoSize()
	local xres, yres = aegisub.video_size()
	return xres, yres
end

function getBackgroundLine(subs, styles)
	--aegisub.debug.out(subs[1].text)
	local firstLine, i = getFirstSubtitleLine(subs)

	if firstLine == nil or string.match(firstLine.text, bgPattern) == nil then
		createBackgroundStyle(subs, styles)
		createBackgroundLine(subs, firstLine, i)
		showMessage(
			tr [[The background shape is missing and now added as first line of subtitle.
Please do flowing steps:
   1- Change background size and position if needed.
   2- Use appropriate style for background.
   3- Run command again.

Note:
   The script will add background to all lines except lines containing {\nobg} command
   or lines with style name ended with _NoBg word (e.g OnScreenText_NoBg)]]
		)
		return nil, true
	end

	return firstLine, false, i
end

function getFirstSubtitleLine(subs)
	for i, l in ipairs(subs) do
		if l.class == "dialogue" then
			l.i = i
			return l, i
		end
	end
	return nil, -1
end

function isStartTimeEqualsPeriorEndTime(line, periorEndTime, secondForContinuousBackground)
	if periorEndTime == "" then
		return false
	end
	local diff = line.start_time - periorEndTime
	return diff < secondForContinuousBackground * 1000
end

function setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime)
	if groupBackgroundIndex == -1 then
		return
	end
	local line = subs[groupBackgroundIndex]
	line.end_time = periorEndTime
	subs[groupBackgroundIndex] = line
end

function createBackgroundStyle(subs, styles)
	local style = styles["TextBackground"]
	if style then
		-- Set existing background style align to 5
		style.align = 5
		updateStyle(subs, style.name, style)
		return
	end
	style = {
		class = "style",
		section = "V4+ Styles",
		name = "TextBackground",
		fontname = "Arial",
		fontsize = "20",
		color1 = "&H46000000&",
		color2 = "&H000000FF&",
		color3 = "&H00000000&",
		color4 = "&H00000000&",
		bold = false,
		italic = false,
		underline = false,
		strikeout = false,
		scale_x = 100,
		scale_y = 100,
		spacing = 0,
		angle = 0,
		borderstyle = 1,
		outline = 0,
		shadow = 0,
		align = 5,
		margin_l = 10,
		margin_r = 10,
		margin_t = 10,
		margin_b = 10,
		encoding = 1
	}
	subs.insert(styles.n, style)
end

function createBackgroundLine(subs, line, idx)
	local bgLine = table.copy(line)
	local videoW, videoH = getVideoSize()
	local margin = videoW / 64
	local shapeHeight = margin * 7
	bgLine.style = "TextBackground"
	bgLine.text =
		string.format(
		"{\\p1\\pos(%d,%d)}m 0 0 l %d 0 l %d %d l 0 %d l 0 0",
		videoW / 2,
		videoH - shapeHeight + margin,
		videoW - 1,
		videoW - 1,
		shapeHeight,
		shapeHeight
	)
	subs.insert(idx, bgLine)
end

function isBackgroundLine(line)
	return string.match(line.text, bgPattern) ~= nil
end

function videoLoaded()
	w = getVideoWidth()
	if w == nil then
		showMessage([[There is no loaded video. 
Please "Open Video..." or "Use Dummy Video..." and try again.]])
		return false
	end
	return true
end

function shouldAddBackground(line)
	return (not string.find(line.style:lower(), "_nobg")) and (not string.find(line.text, "\\nobg")) or
		(string.find(line.style:lower(), "_nobg") and (string.find(line.text, "\\addbg")))
end

function getPositionTag(text)
	local pos = string.match(text, bgPosPattern)
	if pos ~= nil then
		return string.gsub(pos, "\\p1", "")
	end
	return ""
end

function addPositionTag(text, positionTag)
	text = removePosTag(text)
	text = positionTag .. text
	return text
end

function changeStyleAlignToFive(subs, styles, line)
	local style = styles[line.style]
	style.align = 5
	style.outline = 0
	style.shadow = 0
	updateStyle(subs, style.name, style)
	return style
end

function updateStyle(subs, styleName, style)
	for i = 1, #subs do
		local l = subs[i]
		if l.class == "style" and l.name == styleName then
			subs[i] = style
			return
		end
	end
end

--------------------- SplitLine Methods ----------------------------

function getFirstChar(text, chars)
	local sStart = string.len(text)
	local sEnd = 0
	local idx = 0
	for i = 1, #chars do
		local s, e = utf8.find(text, chars[i])
		if s ~= nil and s < sStart then
			sStart = s
			sEnd = e
			idx = i
		end
	end
	return sStart, sEnd, idx
end

function changeLineTimeAterSplit(text, line1, line2)
	start = line1.start_time
	endt = line1.end_time
	dur = endt - start
	--aegisub.log(dur)
	l = dur / utf8.len(text)
	line1.end_time = start + utf8.len(line1.text) * l
	line2.start_time = line1.end_time
	return line1, line2
end

function changeLineTimeAterMove(oldLine, line1, line2)
	if line2.start_time == line2.end_time then
		start = oldLine.start_time
		endt = oldLine.end_time
		dur = endt - start
		l = dur / utf8.len(oldLine.text)
		line1.end_time = start + utf8.len(line1.text) * l
	else
		start = line1.start_time
		endt = line2.end_time
		dur = endt - start
		l = dur / (utf8.len(line1.text) + utf8.len(line2.text))
		line1.end_time = start + utf8.len(line1.text) * l
		line2.start_time = line1.end_time
	end
	return line1, line2
end

function getNumberFromUser(msg, defaultValue)
	config = {
		{class = "label", label = msg, x = 0, y = 0},
		{class = "intedit", name = "inputNumber", value = defaultValue, x = 0, y = 1}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	if btn then
		local r = tonumber(result.inputNumber)
		return r
	end
	return 0
end

function getCharAtIndex(text, index)
	local parts = getTextSplitCharsParts(text)

	if #parts > 0 then
		if index > #parts then
			return nil
		end
		-- -1 means last index of array
		if idx == 0 then
			index = #parts
		end
		-- returns start, end, SplitCharIndex
		return parts[index][1], parts[index][2], parts[index][3]
	end
	return nil
end

function getTextFromUser()
	config = {
		{class = "label", label = "\r\n Enter your code here: \r\n", x = 0, y = 0},
		{class = "textbox", name = "txtCode", value = "{\\ }", x = 0, y = 1, width = 10}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	if btn then
		return result.txtCode
	end
	return nil
end

----------------------- Rtl Correction Methods ---------------------

function removeRtlChars(s)
	local replaced = utf8.gsub(s, rleChar, "")
	local replaced = utf8.gsub(replaced, pdfChar, "")
	return replaced
end

function addRleToEachNoneAlphabeticChars(s)
	local pattern = "([{" .. SpecialChars .. "}])"

	-- Start of right to left embeding character
	local replaced = utf8.gsub(s, pattern, pdfChar .. rleChar .. "%1" .. pdfChar .. rleChar)
	replaced = utf8.gsub(replaced, "\\N", "\\N" .. rleChar)
	return rleChar .. replaced
end

function removeSpacesBeforePunctuationMarks(s)
	local pattern = "(%s+)([{" .. PunctuationMarks .. "}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%2")
	end
	return replaced
end

function addRequiredSpaceAfterPunctuationMarks(s)
	local pattern = "([{" .. PunctuationMarks .. "}])([^%s{" .. PunctuationMarks .. "}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function removeSpaceAfterStartingBrackets(s)
	local pattern = "([{" .. StartingBracketChars .. "}])([%s]+)"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1")
	end
	return replaced
end

function removeSpaceBeforeEndingBrackets(s)
	local pattern = "([%s]+)([{" .. EndingsBracketChars .. "}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%2")
	end
	return replaced
end

function addRequiredSpaceAfterEndingBrackets(s)
	local pattern =
		"([{" ..
		EndingsBracketChars .. "}])([^%s{" .. EndingsBracketChars .. PunctuationMarks .. StartingBracketChars .. '"}])'
	local replaced = s
	if utf8.match(replaced, pattern) then
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function addRequiredSpaceBeforeStartingBrackets(s)
	local pattern = "([^%s{" .. StartingBracketChars .. "}])([{" .. StartingBracketChars .. "}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function isRtl(s)
	local RtlChars = {
		"ء",
		"آ",
		"أ",
		"ا",
		"ب",
		"پ",
		"ت",
		"ة",
		"ث",
		"ج",
		"چ",
		"ح",
		"خ",
		"د",
		"ذ",
		"ر",
		"ز",
		"ژ",
		"س",
		"ش",
		"ص",
		"ض",
		"ط",
		"ظ",
		"ع",
		"غ",
		"ف",
		"ق",
		"ک",
		"ك",
		"گ",
		"ل",
		"م",
		"ن",
		"و",
		"ه",
		"ی",
		"ي"
	}

	local step = utf8.len(s)
	for i = 1, step do
		local ch = utf8.sub(s, i, i)
		--aegisub.log(i.."   "..ch)
		for j = 1, #RtlChars do
			if RtlChars[j] == ch then
				return true
			end
		end
	end
	return false
end

function getSubtitleTextParts(s)
	local text = s
	local parts = {}
	local p1 = "^({.-})"
	local p2 = "^(.-)({.-})"
	local p3 = "({.-})"

	while string.match(text, p3) do
		while string.match(text, p1) do
			local a = string.match(text, p1)
			table.insert(parts, a)
			text = string.gsub(text, p1, "")
		end

		while string.match(text, p2) do
			local a, b = string.match(text, p2)
			table.insert(parts, a)
			table.insert(parts, b)
			text = string.gsub(text, p2, "")
		end
	end

	if utf8.len(text) > 0 then
		table.insert(parts, text)
	end

	return parts
end

function applyRtlCorrection(s)
	if utf8.match(s, CodePattern) == nil then
		s = removeRtlChars(s)
		s = removeDoubleSpace(s)
		s = removeSpacesBeforePunctuationMarks(s)
		s = addRequiredSpaceAfterPunctuationMarks(s)
		s = addRequiredSpaceBeforeStartingBrackets(s)
		s = removeSpaceAfterStartingBrackets(s)
		s = removeSpaceBeforeEndingBrackets(s)
		s = addRequiredSpaceAfterEndingBrackets(s)
		if isRtl(s) then
			s = addRleToEachNoneAlphabeticChars(s)
		end
	end
	return s
end
------------------------------- Rtl Editor Methods ----------------------

function openEditor(str)
	config = {
		{class = "label", label = "\r\n Press Ctrl+Shift to switch to Right to left mode \r\n", x = 0, y = 0},
		{class = "textbox", name = "editor", value = str, x = 0, y = 1, width = 12, height = 8}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	return btn, result.editor
end

------------------------- Move methods -------------------------

function getTextSplitCharsParts(text)
	local parts = {}
	local idx = 0
	text = trim(text)

	for i = 1, #SplitChars do
		txt = text
		local ln = 0
		while txt ~= "" do
			local s, e = utf8.find(txt, SplitChars[i])
			if s then
				table.insert(parts, {})
				table.insert(parts[#parts], ln + s)
				table.insert(parts[#parts], ln + e)
				table.insert(parts[#parts], i)
				txt = utf8.sub(txt, e + 1, utf8.len(txt))
				ln = ln + e
			else
				goto continue
			end
		end
		::continue::
	end

	table.sort(parts, compare)
	return parts
end

function getTextPartsBySplitCharIndexes(parts, text)
	if #parts == 0 then
		return nil
	end
	text = trim(text)
	local start = 1
	local textParts = {}
	for i = 1, #parts do
		local part = utf8.sub(text, start, parts[i][2])
		table.insert(textParts, part)
		start = parts[i][2] + 1
	end
	-- text after last SplitChar
	if start <= utf8.len(text) then
		table.insert(textParts, utf8.sub(text, start))
	end
	return textParts
end

function getLastWord(text)
	local words = {}
	for w in text:gmatch("%S+") do
		table.insert(words, w)
	end
	if (#words == 0) then
		return nil
	end
	return words[#words]
end

function getFirstWord(text)
	local words = {}
	for w in text:gmatch("%S+") do
		table.insert(words, w)
	end
	if (#words == 0) then
		return nil
	end
	return words[1]
end

------------------ Shared Methods -------------------
function string:split(inSplitPattern, outResults)
	if not outResults then
		outResults = {}
	end
	local theStart = 1
	local theSplitStart, theSplitEnd = string.find(self, inSplitPattern, theStart)
	while theSplitStart do
		table.insert(outResults, string.sub(self, theStart, theSplitStart - 1))
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = string.find(self, inSplitPattern, theStart)
	end
	table.insert(outResults, string.sub(self, theStart))
	return outResults
end

function cleanTags(text)
	return string.gsub(text, [[{\.-}]], "")
end

function showMessage(msg)
	config = {
		{class = "label", label = "\r\n" .. msg .. "\r\n", x = 0, y = 0}
	}
	btn, result = aegisub.dialog.display(config, {"OK"}, {ok = "OK"})
end

function compare(a, b)
	return a[1] < b[1]
end

function trim(s)
	local r = s:gsub("^%s*(.-)%s*$", "%1")
	return r
end

function removePosTag(text)
	return string.gsub(text, posPattern, "")
end

function removeDoubleSpace(s)
	while string.match(s, "%s%s") ~= nil do
		s = string.gsub(s, "%s%s", " ")
	end
	return s
end

function secondsToClock(seconds)
	local seconds = tonumber(seconds)

	if seconds <= 0 then
		return "00:00:00"
	else
		hours = string.format("%02.f", math.floor(seconds / 3600))
		mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)))
		secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60))
		return hours .. ":" .. mins .. ":" .. secs
	end
end

function replaceLineBreak(s)
	return utf8.gsub(s, "\\N", "\n")
end


------------------------------ End of methods ------------------------------

aegisub.register_macro(add_background_script_name, tr "Adds background before every line", AddBackground)
aegisub.register_macro(split_script_name, tr "Split selected lines", Split)
aegisub.register_macro(split_at_index_script_name, tr "Split selected line at index", SplitAtIndex)
aegisub.register_macro(rtl_correction_script_name, tr "Corercts Rtl display problem for all line", RtlCorrection)
aegisub.register_macro(
	rtl_correction_selected_line_script_name,
	tr "Corercts Rtl display problem for selected line",
	RtlCorrectorSelectedLine
)
aegisub.register_macro(undo_rtl_correction_script_name, tr "Undo Rtl correction", UndoRtlCorrection)
aegisub.register_macro(show_rtl_editor_script_name, tr "Show Rtl editor", ShowRtlEditor)
aegisub.register_macro(unify_background_lines_script_name, tr "Unify Background Lines", UnifyBackgroundLines)
aegisub.register_macro(add_code_to_selected_lines_script_name, tr "Add Code To Selected Lines", AddCodeToSelectedLines)
aegisub.register_macro(remove_line_break_script_name, tr "Remove line Breaks", RemoveLineBreaks)
aegisub.register_macro(import_text_to_selected_lines, tr "Import text to selected lines", ImportTextToSelectedLines)
aegisub.register_macro(select_playing_line, tr "Select playing line", SelectPlayingLine)
aegisub.register_macro(make_next_line_continuous, tr "Make next line continuous", MakeNextLineContinuous)
aegisub.register_macro(shift_start_line_forward, tr "Shift start line forward", ShiftStartLineForward)
aegisub.register_macro(shift_start_line_backward, tr "Shift start line backward", ShiftStartLineBackward)
aegisub.register_macro(shift_end_line_forward, tr "Shift end line forward", ShiftEndLineForward)
aegisub.register_macro(shift_end_line_backward, tr "Shift end line backward", ShiftEndLineBackward)
aegisub.register_macro(move_last_text_part, tr "Move last text part", MoveLastTextPart)
aegisub.register_macro(move_first_part_of_next, tr "Move first part of next", MoveFirstPartOfNext)
aegisub.register_macro(move_last_word, tr "Move last word", MoveLastWord)
aegisub.register_macro(move_first_word_of_next, tr "Move first word of next", MoveFirstWordOfNext)
aegisub.register_macro(remove_position_tags, tr "Remove Position tags", RemovePositionTags)
aegisub.register_macro(display_sum_of_times, tr "Display sum of times", DisplaySumOfTimes)
aegisub.register_macro(generate_srt_like_text, tr "Generate SRT like text", GenerateSrtLikeText)
