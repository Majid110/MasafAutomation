include("karaskel.lua")

local tr = aegisub.gettext
local utf8 = require "utf8"
--local inspect = require "inspect"

add_background_script_name = tr "Masaf/Add Backgrounds"
remove_background_lines = tr "Masaf/Remove all Background lines"

------------ Corrections -------------
rtl_correction_script_name = tr "Masaf/Correction/Rtl Correction - All lines"
rtl_correction_selected_line_script_name = tr "Masaf/Correction/Rtl Correction - Selected"
undo_rtl_correction_script_name = tr "Masaf/Correction/Undo Rtl Correction - Selected"
convert_numbers_to_english = tr "Masaf/Correction/Convert Numbers to English"
convert_numbers_to_arabic = tr "Masaf/Correction/Convert Numbers to Arabic"
convert_numbers_to_persian = tr "Masaf/Correction/Convert Numbers to Persian"

------------ Text Movements -------------
shift_start_line_forward = tr "Masaf/Text Movement/Shift start line forward"
shift_start_line_backward = tr "Masaf/Text Movement/Shift start line backward"
shift_end_line_forward = tr "Masaf/Text Movement/Shift end line forward"
shift_end_line_backward = tr "Masaf/Text Movement/Shift end line backward"
move_last_text_part = tr "Masaf/Text Movement/Move last text part"
move_first_part_of_next = tr "Masaf/Text Movement/Move first part of next"
move_last_word = tr "Masaf/Text Movement/Move last word"
move_first_word_of_next = tr "Masaf/Text Movement/Move first word of next"

split_script_name = tr "Masaf/Split line"
split_at_index_script_name = tr "Masaf/Split line at Index"
show_rtl_editor_script_name = tr "Masaf/Show Rtl Editor"
make_next_line_continuous = tr "Masaf/Make next line continuous"
remove_line_break_script_name = tr "Masaf/Remove line Breaks"
remove_position_tags = tr "Masaf/Remove Position tags"
select_playing_line = tr "Masaf/Select playing line"
generate_srt_like_text = tr "Masaf/Generate SRT like text"

------------ Special Tags ------------
fix_line_position = tr "Masaf/Special Tags/Fix line Position"
set_line_as_no_background = tr "Masaf/Special Tags/Set line as No Background"
set_line_as_dont_correct_rtl = tr "Masaf/Special Tags/Set line as Don't Correct RTL"
set_line_as_dont_remove = tr "Masaf/Special Tags/Set line as Don't Remove"

------------ Miscs ------------
unify_background_lines_script_name = tr "Masaf/Misc/Unify Background lines"
add_code_to_selected_lines_script_name = tr "Masaf/Misc/Add Code to Selected lines"
import_text_to_selected_lines = tr "Masaf/Misc/Import text to selected Lines"
display_sum_of_times = tr "Masaf/Misc/Display sum of times"

script_description = tr "Some Aegisub automation scripts specially designed for Right-To-Left language subtitles"
script_author = "Majid Shamkhani"
script_version = "1.19.2"

-- <<<<<<<<<<<<<<<<<<<<<<<<< Main Methods >>>>>>>>>>>>>>>>>>>>>>>>>

-- ------------------------- AddBackground ---------------------

BgPattern = [[{\p1\pos%(.-%)}m %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+]]
PosPattern = "^{\\pos%(.-%)}"
BgPosPattern = "^{\\p1\\pos%(.-%)}"
SplitChars = {"||", "\\N", "%.", ",", "،", ";", "%?", "؟", "!", ":", "؛", "۔"}

RleChar = utf8.char(0x202B)
PdfChar = utf8.char(0x202C)

FixedPosTag = "\\fixedpos"
NoBgTag = "\\nobg" -- No Background
DcrtlTag = "\\dcrtl" -- Dont Correct RTL
Drl = "\\drl" -- Dont Remove Line

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

	local secondForContinuousBackground, dialogOk =
		getNumberFromUser("\r\n Enter maximum second to make background continious: \r\n", 1)

	if not dialogOk then
		return
	end

	local lastLineStyle = nil
	while i < n do
		i = i + 1

		aegisub.progress.task("Processing line " .. i .. "/" .. n)
		aegisub.progress.set(i / n * 100)

		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and shouldAddBackground(l) then
			-- remove already added background line
			if bgShape ~= nil and i ~= bgShape.i and isBackgroundLine(l) then
				if canRemoveBackground(l) then
					subs.delete(i)
					i = i - 1
					n = n - 1
				end
				goto continue
			end

			-- Set text style align to 5 once.
			if lastLineStyle == nil or lastLineStyle ~= l.name then
				lastLineStyle = changeStyleAlignToFive(subs, styles, l)
			end

			if not string.find(l.text, FixedPosTag) then
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

			::continue::
		end
	end

	if groupCount > 0 then
		setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime)
	end

	aegisub.set_undo_point(add_background_script_name)
end

------------------------------ Split Line -----------------------------

function Split(subs, selected)
	if #selected > 1 then
		return
	end
	local index = selected[1]
	local textParts = {}
	local line = subs[index]
	local text = line.text

	local line2 = table.copy(line)

	-- Finding manual splittnig symbol -> ||
	s, e = utf8.find(text, SplitChars[1])
	if s then
		line.text = utf8.sub(text, 1, s - 1)
		line2.text = utf8.sub(text, e + 1, utf8.len(text))
		line.text = rtlCorrectNonCodeText(trim(line.text))
		line2.text = rtlCorrectNonCodeText(trim(line2.text))
		changeLineTimeAfterSplit(text, line, line2)
		subs[index] = line
		subs.insert(index + 1, line2)
		goto continue
	end

	textParts = getSubtitleTextParts(text)

	s, e, idx = getFirstChar(text, textParts)
	if idx > 0 then
		-- Remove split char from end of text
		if idx <= 2 then
			line.text = utf8.sub(text, 1, s - 1)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		else
			line.text = utf8.sub(text, 1, e)
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		end
		changeLineTimeAfterSplit(text, line, line2)
		line.text = rtlCorrectNonCodeText(trim(line.text))
		line2.text = rtlCorrectNonCodeText(trim(line2.text))
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

	local idx, dialogOk =
		getNumberFromUser("\r\n Enter index of character that you want to split line on that character: \r\n", 2)

	if not dialogOk then
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
		changeLineTimeAfterSplit(text, line, line2)
		line.text = rtlCorrectNonCodeText(trim(line.text))
		line2.text = rtlCorrectNonCodeText(trim(line2.text))
		subs[selected[1]] = line
		subs.insert(selected[1] + 1, line2)
	end

	aegisub.set_undo_point(split_at_index_script_name)
	return selected
end

--------------------------- RtlCorrection ---------------------

local SpecialChars = [[%.,،%?؟«»!%-:]]
local PunctuationMarks = [[%.,،%?؟:؛!;۔]]
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
		if l.class == "dialogue" and l.effect == "" and not l.comment and canCorrectRtl(l.text) then
			if not isBackgroundLine(l) then
				local parts = getSubtitleTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					t = rtlCorrectNonCodeText(t)
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

	if (not isBackgroundLine(line)) then
		line.text = rtlCorrectIfAllowed(line.text)
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
	local textParts = getSubtitleTextParts(line.text)
	local codeText, plainText = getCodeAndPlainTextPart(line.text, textParts)
	local sourceText = utf8.gsub(plainText, "\\N", "\n")
	local result, newText = openEditor(sourceText)

	if not result then
		return
	end
	-- Replace line break with \N
	newText = utf8.gsub(newText, "\n", "\\N")
	newText = rtlCorrectNonCodeText(newText)
	line.text = codeText .. newText
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
	line.text = removeDoubleSpace(line.text)
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
	local fr2ms = aegisub.ms_from_frame

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
	local oldLine = table.copy(line)

	local text, code = removeRtlChars(line.text), ""
	local textParts = getSubtitleTextParts(text)
	code, text = getCodeAndPlainTextPart(text, textParts)

	local parts = getTextSplitCharsParts(text)
	if #parts == 0 then
		return
	end
	local textParts = getTextPartsBySplitCharIndexes(parts, text)

	text = ""
	for i = 1, #textParts - 1, 1 do
		text = text .. textParts[i] .. " "
	end

	local nextText, nextCode = removeRtlChars(trim(nextLine.text)), ""
	local nextTextParts = getSubtitleTextParts(nextText)
	nextCode, nextText = getCodeAndPlainTextPart(nextText, nextTextParts)

	nextText = textParts[#textParts] .. " " .. nextText
	line.text = code .. rtlCorrectIfAllowed(text)
	nextLine.text = nextCode .. rtlCorrectIfAllowed(nextText)
	changeLineTimeAfterMove(oldLine, line, nextLine)
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

	local nextText, nextCode = ""
	nextText = removeRtlChars(nextLine.text)
	local nextTextParts = getSubtitleTextParts(nextText)
	nextCode, nextText = getCodeAndPlainTextPart(nextText, nextTextParts)

	local oldLine = table.copy(line)
	local parts = getTextSplitCharsParts(nextText)
	if #parts == 0 then
		return
	end
	local textParts = getTextPartsBySplitCharIndexes(parts, nextText)

	nextText = ""
	for i = 2, #textParts, 1 do
		nextText = nextText .. textParts[i] .. " "
	end

	nextText = nextCode .. nextText
	nextLine.text = rtlCorrectIfAllowed(nextText)

	local text = removeRtlChars(line.text)
	text = text .. " " .. trim(textParts[1])
	line.text = rtlCorrectIfAllowed(text)

	changeLineTimeAfterMove(oldLine, line, nextLine)
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
	local text = trim(removeRtlChars(line.text))
	local oldLine = table.copy(line)
	local lastWord = getLastWord(text)
	if lastWord == nil then
		return
	end

	local textLen = utf8.len(text)
	line.text = utf8.sub(text, 1, textLen - utf8.len(lastWord) - 1)

	local nextText, nextCode = removeRtlChars(nextLine.text), ""
	local textParts = getSubtitleTextParts(nextText)
	nextCode, nextText = getCodeAndPlainTextPart(text, textParts)

	nextText = nextCode .. lastWord .. " " .. nextText
	line.text = rtlCorrectIfAllowed(trim(line.text))
	nextLine.text = rtlCorrectIfAllowed(trim(nextText))
	changeLineTimeAfterMove(oldLine, line, nextLine)
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

	local text, code = removeRtlChars(trim(nextLine.text)), ""
	local textParts = getSubtitleTextParts(text)
	code, text = getCodeAndPlainTextPart(text, textParts)

	local oldLine = table.copy(line)
	local firstWord = getFirstWord(text)
	if firstWord == nil then
		return
	end

	line.text = line.text .. " " .. firstWord
	line.text = rtlCorrectIfAllowed(line.text)

	text = code .. utf8.sub(text, utf8.len(firstWord) + 2, utf8.len(text))
	nextLine.text = rtlCorrectIfAllowed(text)

	changeLineTimeAfterMove(oldLine, line, nextLine)
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

---------------------- Remove Background Lines -------------------------
function RemoveBackgroundLines(subs)
	local i, n = 0, #subs
	n = subs.n
	while i < n do
		i = i + 1
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and isBackgroundLine(l) then
			subs.delete(i)
			i = i - 1
			n = n - 1
		end
	end
	aegisub.set_undo_point(remove_background_lines)
end

---------------------- Number Converters -------------------------
function ConvertNumbersToEnglish(subs)
	local i, n = 0
	n = subs.n

	while i < n do
		i = i + 1
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and canCorrectRtl(l.text) then
			if not isBackgroundLine(l) then
				local parts = getSubtitleTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					t = applyNumbersToEnglish(t)
					text = text .. t
				end
				l.text = text
				subs[i] = l
			end
		end
	end

	aegisub.set_undo_point(convert_numbers_to_english)
end

function ConvertNumbersToArabic(subs)
	local i, n = 0
	n = subs.n

	while i < n do
		i = i + 1
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and canCorrectRtl(l.text) then
			if not isBackgroundLine(l) then
				local parts = getSubtitleTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					t = applyNumbersToArabic(t)
					text = text .. t
				end
				l.text = text
				subs[i] = l
			end
		end
	end

	aegisub.set_undo_point(convert_numbers_to_arabic)
end

function ConvertNumbersToPersian(subs)
	local i, n = 0
	n = subs.n

	while i < n do
		i = i + 1
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and canCorrectRtl(l.text) then
			if not isBackgroundLine(l) then
				local parts = getSubtitleTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					t = applyNumbersToPersian(t)
					text = text .. t
				end
				l.text = text
				subs[i] = l
			end
		end
	end

	aegisub.set_undo_point(convert_numbers_to_arabic)
end

function FixLinePosition(subs, selected)
	addTag(subs, selected, FixedPosTag)
	aegisub.set_undo_point(fix_line_position)
end

function SetLineAsNoBackground(subs, selected)
	addTag(subs, selected, NoBgTag)
	aegisub.set_undo_point(set_line_as_no_background)
end

function SetLineAsDontCorrectRtl(subs, selected)
	addTag(subs, selected, DcrtlTag)
	aegisub.set_undo_point(set_line_as_dont_correct_rtl)
end

function SetLineAsDontRemove(subs, selected)
	addTag(subs, selected, Drl)
	aegisub.set_undo_point(set_line_as_dont_remove)
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

	if firstLine == nil or string.match(firstLine.text, BgPattern) == nil then
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
	return string.match(line.text, BgPattern) ~= nil
end

function videoLoaded()
	local w = getVideoWidth()
	if w == nil then
		showMessage([[There is no loaded video. 
Please "Open Video..." or "Use Dummy Video..." and try again.]])
		return false
	end
	return true
end

function shouldAddBackground(line)
	return (not string.find(line.style:lower(), "_nobg")) and (not string.find(line.text, NoBgTag)) or
		(string.find(line.style:lower(), "_nobg") and (string.find(line.text, "\\addbg")))
end

function getPositionTag(text)
	local pos = string.match(text, BgPosPattern)
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
	style.shadow = 1
	style.borderstyle = 1
	updateStyle(subs, style.name, style)
	return style.name
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

function canRemoveBackground(line)
	return not string.find(line.text, Drl)
end

--------------------- SplitLine Methods ----------------------------

function getFirstChar(text, textParts)
	local sStart = 0
	local sEnd = 0
	local idx = 0

	local codeText, plainText = getCodeAndPlainTextPart(text, textParts)
	local codeLength = string.len(codeText)
	sStart = string.len(plainText)

	for i = 1, #SplitChars do
		local s, e = utf8.find(plainText, SplitChars[i])
		if s ~= nil and s < sStart then
			sStart = s
			sEnd = e
			idx = i
		end
	end
	return sStart + codeLength, sEnd + codeLength, idx
end

function changeLineTimeAfterSplit(text, line1, line2)
	local start = line1.start_time
	local endt = line1.end_time
	local dur = endt - start
	--aegisub.log(dur)
	local l = dur / utf8.len(text)
	line1.end_time = start + utf8.len(line1.text) * l
	line2.start_time = line1.end_time
	return line1, line2
end

function changeLineTimeAfterMove(oldLine, line1, line2)
	local start, endt, dur, l = 0

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
	local config = {
		{class = "label", label = msg, x = 0, y = 0},
		{class = "intedit", name = "inputNumber", value = defaultValue, x = 0, y = 1}
	}
	local btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	if btn then
		local r = tonumber(result.inputNumber)
		return r, true
	end
	return 0, false
end

function getCharAtIndex(text, index)
	local parts = getTextSplitCharsParts(text)

	if #parts > 0 then
		if index > #parts then
			return nil
		end
		-- -1 means last index of array
		-- if idx == 0 then
		--	index = #parts
		-- end

		-- returns start, end, SplitCharIndex
		return parts[index][1], parts[index][2], parts[index][3]
	end
	return nil
end

function getTextFromUser()
	local config = {
		{class = "label", label = "\r\n Enter your code here: \r\n", x = 0, y = 0},
		{class = "textbox", name = "txtCode", value = "{\\ }", x = 0, y = 1, width = 10}
	}
	local btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	if btn then
		return result.txtCode
	end
	return nil
end

----------------------- Rtl Correction Methods ---------------------

function removeRtlChars(s)
	local lreChar = utf8.char(0x202A)
	local lroChar = utf8.char(0x202D)
	local rloChar = utf8.char(0x202E)
	local replaced = utf8.gsub(s, RleChar, "")
	local replaced = utf8.gsub(replaced, PdfChar, "")
	local replaced = utf8.gsub(replaced, lreChar, "")
	local replaced = utf8.gsub(replaced, lroChar, "")
	local replaced = utf8.gsub(replaced, rloChar, "")
	return replaced
end

function addRleToEachNoneAlphabeticChars(s)
	local pattern = "([{" .. SpecialChars .. "}])"

	-- Start of right to left embeding character
	local replaced = utf8.gsub(s, pattern, PdfChar .. RleChar .. "%1" .. PdfChar .. RleChar)
	replaced = utf8.gsub(replaced, "\\N", "\\N" .. RleChar)
	return RleChar .. replaced
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
		"ي",
		"۔"
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

function rtlCorrectNonCodeText(s)
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

function canCorrectRtl(text)
	-- dcrtl = dont correct rtl
	local canCorrect = not string.find(text, DcrtlTag)
	return canCorrect
end

function rtlCorrectTextWithCode(s)
	local parts = getSubtitleTextParts(s)
	local text = ""
	for k = 1, #parts do
		local t = parts[k]
		t = rtlCorrectNonCodeText(t)
		text = text .. t
	end
	return text
end

function rtlCorrectIfAllowed(s)
	if not canCorrectRtl(s) then
		return s
	end
	return rtlCorrectTextWithCode(s)
end
------------------------------- Rtl Editor Methods ----------------------

function openEditor(str)
	local config = {
		{class = "label", label = "\r\n Press Ctrl+Shift to switch to Right to left mode \r\n", x = 0, y = 0},
		{class = "textbox", name = "editor", value = str, x = 0, y = 1, width = 12, height = 8}
	}
	local btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok = "OK", cancel = "Cancel"})
	return btn, result.editor
end

------------------------- Move methods -------------------------

function getTextSplitCharsParts(text)
	local parts = {}
	text = trim(text)

	for i = 1, #SplitChars do
		local txt = text
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

	-- if text not contains any SplitChars
	if #parts == 0 and text ~= "" then
		table.insert(parts, {})
		table.insert(parts[#parts], 1)
		table.insert(parts[#parts], utf8.len(text))
		table.insert(parts[#parts], 1)
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

------------------ Number Converter Methods -------------------
function applyNumbersToEnglish(text)
	-- Persian numbers to English
	if utf8.match(text, CodePattern) == nil then
		text = utf8.gsub(text, "۱", "1")
		text = utf8.gsub(text, "۲", "2")
		text = utf8.gsub(text, "۳", "3")
		text = utf8.gsub(text, "۴", "4")
		text = utf8.gsub(text, "۵", "5")
		text = utf8.gsub(text, "۶", "6")
		text = utf8.gsub(text, "۷", "7")
		text = utf8.gsub(text, "۸", "8")
		text = utf8.gsub(text, "۹", "9")
		text = utf8.gsub(text, "۰", "0")

		-- Arabic numbers to English
		text = utf8.gsub(text, "١", "1")
		text = utf8.gsub(text, "٢", "2")
		text = utf8.gsub(text, "٣", "3")
		text = utf8.gsub(text, "٤", "4")
		text = utf8.gsub(text, "٥", "5")
		text = utf8.gsub(text, "٦", "6")
		text = utf8.gsub(text, "٧", "7")
		text = utf8.gsub(text, "٨", "8")
		text = utf8.gsub(text, "٩", "9")
		text = utf8.gsub(text, "٠", "0")
	end
	return text
end

function applyNumbersToArabic(text)
	if utf8.match(text, CodePattern) == nil then
		-- Persian numbers to Arabic
		text = utf8.gsub(text, "۱", "١")
		text = utf8.gsub(text, "۲", "٢")
		text = utf8.gsub(text, "۳", "٣")
		text = utf8.gsub(text, "۴", "٤")
		text = utf8.gsub(text, "۵", "٥")
		text = utf8.gsub(text, "۶", "٦")
		text = utf8.gsub(text, "۷", "٧")
		text = utf8.gsub(text, "۸", "٨")
		text = utf8.gsub(text, "۹", "٩")
		text = utf8.gsub(text, "۰", "٠")

		-- English numbers to Arabic
		text = utf8.gsub(text, "1", "١")
		text = utf8.gsub(text, "2", "٢")
		text = utf8.gsub(text, "3", "٣")
		text = utf8.gsub(text, "4", "٤")
		text = utf8.gsub(text, "5", "٥")
		text = utf8.gsub(text, "6", "٦")
		text = utf8.gsub(text, "7", "٧")
		text = utf8.gsub(text, "8", "٨")
		text = utf8.gsub(text, "9", "٩")
		text = utf8.gsub(text, "0", "٠")
	end
	return text
end

function applyNumbersToPersian(text)
	if utf8.match(text, CodePattern) == nil then
		-- Arabic numbers to Persian
		text = utf8.gsub(text, "١", "۱")
		text = utf8.gsub(text, "٢", "۲")
		text = utf8.gsub(text, "٣", "۳")
		text = utf8.gsub(text, "٤", "۴")
		text = utf8.gsub(text, "٥", "۵")
		text = utf8.gsub(text, "٦", "۶")
		text = utf8.gsub(text, "٧", "۷")
		text = utf8.gsub(text, "٨", "۸")
		text = utf8.gsub(text, "٩", "۹")
		text = utf8.gsub(text, "٠", "۰")

		-- English numbers to Persian
		text = utf8.gsub(text, "1", "۱")
		text = utf8.gsub(text, "2", "۲")
		text = utf8.gsub(text, "3", "۳")
		text = utf8.gsub(text, "4", "۴")
		text = utf8.gsub(text, "5", "۵")
		text = utf8.gsub(text, "6", "۶")
		text = utf8.gsub(text, "7", "۷")
		text = utf8.gsub(text, "8", "۸")
		text = utf8.gsub(text, "9", "۹")
		text = utf8.gsub(text, "0", "۰")
	end
	return text
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
	local config = {
		{class = "label", label = "\r\n" .. msg .. "\r\n", x = 0, y = 0}
	}
	local btn, result = aegisub.dialog.display(config, {"OK"}, {ok = "OK"})
end

function compare(a, b)
	return a[1] < b[1]
end

function trim(s)
	local r = s:gsub("^%s*(.-)%s*$", "%1")
	return r
end

function removePosTag(text)
	return string.gsub(text, PosPattern, "")
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
		local hours = string.format("%02.f", math.floor(seconds / 3600))
		local mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)))
		local secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60))
		return hours .. ":" .. mins .. ":" .. secs
	end
end

function replaceLineBreak(s)
	return utf8.gsub(s, "\\N", "\n")
end

function addTag(subs, selected, tag)
	for i = 1, #selected, 1 do
		local line = subs[selected[i]]
		line.text = "{" .. tag .. "}" .. line.text
		subs[selected[i]] = line
	end
end

function getCodeAndPlainTextPart(text, textParts)
	local plainText = ""
	local codeText = ""
	local codeIndex = 0

	if #textParts > 0 then
		for i = 1, #textParts do
			if utf8.match(textParts[i], CodePattern) == nil then
				break
			end
			codeIndex = i
			codeText = codeText .. textParts[i]
		end

		if codeIndex > 0 then
			for i = codeIndex + 1, #textParts do
				plainText = plainText .. textParts[i]
			end
		else
			plainText = text
		end
	end
	return codeText, plainText
end

------------------------------ End of methods ------------------------------

aegisub.register_macro(add_background_script_name, tr "Adds background before every line", AddBackground)
aegisub.register_macro(remove_background_lines, tr "Remove all Background lines", RemoveBackgroundLines)

------------ Corrections -------------
aegisub.register_macro(rtl_correction_script_name, tr "Corercts Rtl display problem for all lines", RtlCorrection)
aegisub.register_macro(undo_rtl_correction_script_name, tr "Undo Rtl correction", UndoRtlCorrection)
aegisub.register_macro(
	rtl_correction_selected_line_script_name,
	tr "Corercts Rtl display problem for selected line",
	RtlCorrectorSelectedLine
)
aegisub.register_macro(convert_numbers_to_english, tr "Convert Numbers to English", ConvertNumbersToEnglish)
aegisub.register_macro(convert_numbers_to_arabic, tr "Convert Numbers to Arabic", ConvertNumbersToArabic)
aegisub.register_macro(convert_numbers_to_persian, tr "Convert Numbers to Persian", ConvertNumbersToPersian)

------------ Text Movements -------------
aegisub.register_macro(shift_start_line_forward, tr "Shift start line forward", ShiftStartLineForward)
aegisub.register_macro(shift_start_line_backward, tr "Shift start line backward", ShiftStartLineBackward)
aegisub.register_macro(shift_end_line_forward, tr "Shift end line forward", ShiftEndLineForward)
aegisub.register_macro(shift_end_line_backward, tr "Shift end line backward", ShiftEndLineBackward)
aegisub.register_macro(move_last_text_part, tr "Move last text part", MoveLastTextPart)
aegisub.register_macro(move_first_part_of_next, tr "Move first part of next", MoveFirstPartOfNext)
aegisub.register_macro(move_last_word, tr "Move last word", MoveLastWord)
aegisub.register_macro(move_first_word_of_next, tr "Move first word of next", MoveFirstWordOfNext)

aegisub.register_macro(split_script_name, tr "Split selected lines", Split)
aegisub.register_macro(split_at_index_script_name, tr "Split selected line at index", SplitAtIndex)
aegisub.register_macro(show_rtl_editor_script_name, tr "Show Rtl editor", ShowRtlEditor)
aegisub.register_macro(make_next_line_continuous, tr "Make next line continuous", MakeNextLineContinuous)
aegisub.register_macro(remove_line_break_script_name, tr "Remove line Breaks", RemoveLineBreaks)
aegisub.register_macro(remove_position_tags, tr "Remove Position tags", RemovePositionTags)
aegisub.register_macro(select_playing_line, tr "Select playing line", SelectPlayingLine)
aegisub.register_macro(generate_srt_like_text, tr "Generate SRT like text", GenerateSrtLikeText)

------------ Special Tags ------------
aegisub.register_macro(fix_line_position, tr "Fix line Position", FixLinePosition)
aegisub.register_macro(set_line_as_no_background, tr "Set line as No Background", SetLineAsNoBackground)
aegisub.register_macro(set_line_as_dont_correct_rtl, tr "Set line as Don't Correct RTL", SetLineAsDontCorrectRtl)
aegisub.register_macro(set_line_as_dont_remove, tr "Set line as Don't Remove", SetLineAsDontRemove)

------------ Miscs ------------
aegisub.register_macro(unify_background_lines_script_name, tr "Unify Background Lines", UnifyBackgroundLines)
aegisub.register_macro(add_code_to_selected_lines_script_name, tr "Add Code To Selected Lines", AddCodeToSelectedLines)
aegisub.register_macro(import_text_to_selected_lines, tr "Import text to selected lines", ImportTextToSelectedLines)
aegisub.register_macro(display_sum_of_times, tr "Display sum of times", DisplaySumOfTimes)
