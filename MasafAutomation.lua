
include("karaskel.lua")

local tr = aegisub.gettext
local utf8 = require "utf8"
--local inspect = require "inspect"

add_background_script_name = tr"Masaf/Add All Backgrounds"
add_selected_background_script_name = tr"Masaf/Add Selected Background"
split_script_name = tr"Masaf/Split line"
split_at_index_script_name = tr"Masaf/Split line at Index"
rtl_correction_script_name = tr"Masaf/Rtl Correction - All line"
rtl_correction_selected_line_script_name = tr"Masaf/Rtl Correction - Selected"
undo_rtl_correction_script_name = tr"Masaf/Undo Rtl Correction - Selected"
show_rtl_editor_script_name = tr"Masaf/Show Rtl Editor"
unify_background_lines_script_name = tr"Masaf/Unify Background lines"
add_code_to_selected_lines_script_name = tr"Masaf/Add Code to Selected lines"
remove_line_break_script_name = tr"Masaf/Remove line Breaks"
import_text_to_selected_lines = tr"Masaf/Import text to selected Lines"

script_description = tr"Some Aegisub automation scripts specially designed for Right-To-Left language subtitles"
script_author = "Majid Shamkhani"
script_version = "1.5"

-- <<<<<<<<<<<<<<<<<<<<<<<<< Main Methods >>>>>>>>>>>>>>>>>>>>>>>>>

-- ------------------------- AddBackground ---------------------

bgPattern = [[{\p1\pos%(.-%)}m %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+ l %d+ %d+]]
bgTransformPattern = [[({\p1\pos%(.-%)}m %d+ %d+ l %d+ %d+ l %d+ )(%d+)( l %d+ )(%d+)( l %d+ %d+)]]

function AddBackground(subs)

	if not videoLoaded() then return end

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
	if doExit then return end

	while i < n do
		i = i + 1
		
		aegisub.progress.task("Processing line "..i.."/"..n)
		aegisub.progress.set(i/n*100)
		
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment and mayAddBackground(l) then

			-- remove already added background line
			if bgShape ~= nil and i ~= bgShape.i and isBackgroundLine(l) then
				subs.delete(i)
				i = i - 1
				n = n - 1
				goto continue
			end

			local startTimeEqualsPeriorEndTime = isStartTimeEqualsPeriorEndTime(l, periorEndTime)

			local currentLineCount = calcLineCount(l, styles);

			if not startTimeEqualsPeriorEndTime or lastLineCount ~= currentLineCount then
				l.i = i
				l.comment = false
				local bgLine = generateBackground(subs, styles, l, bgShape)

				if groupBackgroundIndex ~= -1 and groupCount > 0 then
					setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime);
					groupCount = 0;
				end				
				subs.insert(i, bgLine)
				groupBackgroundIndex = i;
				i = i + 1
				n = n + 1
			else
				groupCount  = groupCount + 1;
			end

			periorEndTime = l.end_time
			lastLineCount = calcLineCount(l, styles)

			::continue::
		end
	end

	if groupCount > 0 then
		setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime);
	end

	aegisub.set_undo_point(add_background_script_name)
end

------------------------- AddSelectedBackground ---------------------------

function AddSelectedBackground(subs, selected)

	if not videoLoaded() then return end

	if #selected > 1 then return end

	local meta, styles = karaskel.collect_head(subs)
	local line = subs[selected[1]]

	local meta, styles = karaskel.collect_head(subs)
	-- start processing lines
	local i, n = 0
	n = subs.n
	local periorEndTime = ""
	local groupBackgroundIndex = -1
	local groupCount = 0
	local lastLineCount = 0

	local bgShape, doExit = getBackgroundLine(subs, styles)
	
	-- Missing background shape
	-- Adding new shape line and exit
	if doExit then return end

	i = selected[1] - 1
	
	while i < n do
		i = i + 1
		--aegisub.progress.set(i/n*100)
		
		local l = subs[i]
		if l.class == "dialogue" and l.effect == "" and not l.comment then

			local startTimeEqualsPeriorEndTime = isStartTimeEqualsPeriorEndTime(l, periorEndTime)

			local currentLineCount = calcLineCount(l, styles);

			if not startTimeEqualsPeriorEndTime or lastLineCount ~= currentLineCount then

				-- End of group background position, must be exiting
				if groupBackgroundIndex ~= -1 then
					goto continue
				end

				l.i = i
				l.comment = false
				local bgLine = generateBackground(subs, styles, l, bgShape)

				if groupBackgroundIndex ~= -1 and groupCount > 0 then
					setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime);
					groupCount = 0;
				end				
				subs.insert(i, bgLine)
				groupBackgroundIndex = i;
				i = i + 1
				n = n + 1
			else
				groupCount  = groupCount + 1;
			end

			periorEndTime = l.end_time
			lastLineCount = calcLineCount(l, styles)
		end
	end

	::continue::

	if groupCount > 0 then
		setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime);
	end

	aegisub.set_undo_point(add_selected_background_script_name)
end

------------------------------ Split Line -----------------------------

local SplitChars = {"||", "\\N", "%.", ",", "،", ";", "%?", "؟", "!", ":"}

function Split(subs,sel)
	for i = #sel, 1, -1 do
		line = subs[sel[i]]
		text = line.text

		line2 = table.copy(line)

		-- Finding manual splittnig symbol -> ||
		local s, e = string.find(text, SplitChars[1])
		if s then
			line.text = string.sub(text, 1, s - 1) 
			line2.text = string.sub(text, e + 1, string.len(text))
			ChangeLineTime(text, line, line2)
			subs[sel[i]] = line
			subs.insert(sel[i] + 1, line2)			
			goto continue
		end


		s, e, idx = GetFirstChar(text, SplitChars)
		if e > 0 then 
			-- Remove split char from end of text
			if idx <= 2 then
				line.text = string.sub(text, 1, s - 1) 
				line2.text = string.sub(text, e + 1, string.len(text))
			else
				line.text = string.sub(text, 1, e) 
				line2.text = string.sub(text, e + 1, string.len(text))
			end
			ChangeLineTime(text, line, line2)
			subs[sel[i]] = line
			subs.insert(sel[i] + 1, line2)			
		end
	end

	::continue::

	aegisub.set_undo_point(split_script_name)
	return sel
end

-- -------------------------SplitAtIndex ---------------------

function SplitAtIndex(subs,selected)

	if #selected > 1 then return end
	local line = subs[selected[1]]

	text = line.text

	line2 = table.copy(line)

	local idx = GetIndexFromUser()
	
	if idx == 0 then return end

	local s, e, idx = GetCharAtIndex(text, idx)
	if s then 
		-- Remove split char from end of text
		if idx <= 2 then
			line.text = utf8.sub(text, 1, s - 1) 
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		else
			line.text = utf8.sub(text, 1, e) 
			line2.text = utf8.sub(text, e + 1, utf8.len(text))
		end
		ChangeLineTime(text, line, line2)
		subs[selected[1]] = line
		subs.insert(selected[1] + 1, line2)			
	end

	aegisub.set_undo_point(split_at_index_script_name)
	return selected
end

--------------------------- RtlCorrection ---------------------

local SpecialChars = [[%.,،%?؟«»!%-:]]
local PunctuationMarks = [[%.,،%?؟:؛!;]]
local StartingBracketChars = [[%({%[<«]]
local EndingsBracketChars = [[%)}%]>»]]
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
				local parts = GetTextParts(l.text)
				local text = ""
				for k = 1, #parts do
					local t = parts[k]
					if utf8.match(t, CodePattern) == nil then
						--t = Trim(t)
						t = RemoveRle(t)
						t = RemoveDoubleSpace(t)
						t = RemoveSpacesBeforePunctuationMarks(t)
						t = AddRequiredSpaceAfterPunctuationMarks(t)
						t = AddRequiredSpaceBeforeStartingBrackets(t)
						t = RemoveSpaceAfterStartingBrackets(t)
						t = RemoveSpaceBeforeEndingBrackets(t)
						t = AddRequiredSpaceAfterEndingBrackets(t)
						if IsRtl(t) then
							t = AddRleToEachNoneAlphabeticChars(t)
						end
					end
					text = text..t
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

	if #selected > 1 then return end

	local line = subs[selected[1]]

	-- start processing lines

	if not isBackgroundLine(line) then 
		local parts = GetTextParts(line.text)
		local text = ""
		for k = 1, #parts do
			local t = parts[k]
			if utf8.match(t, CodePattern) == nil then
				--t = Trim(t)
				t = RemoveRle(t)
				t = RemoveDoubleSpace(t)
				t = RemoveSpacesBeforePunctuationMarks(t)
				t = AddRequiredSpaceBeforeStartingBrackets(t)
				t = RemoveSpaceAfterStartingBrackets(t)
				t = RemoveSpaceBeforeEndingBrackets(t)
				t = AddRequiredSpaceAfterEndingBrackets(t)
				if IsRtl(t) then
					t = AddRleToEachNoneAlphabeticChars(t)
				end
			end
			text = text..t
		end
		line.text = text
		subs[selected[1]] = line
	end

	aegisub.set_undo_point(rtl_correction_selected_line_script_name)
end

------------------------------ Undo Rtl Correction ----------------------------

function UndoRtlCorrection(subs, selected)
	
	if #selected > 1 then return end
	local line = subs[selected[1]]
	line.text = RemoveRle(line.text)
	subs[selected[1]] = line

	aegisub.set_undo_point(undo_rtl_correction_script_name)
end

------------------------------ Show Rtl Editor ---------------------------------

function ShowRtlEditor(subs, selected)
	
	if #selected > 1 then return end
	local line = subs[selected[1]]
	local result, text = OpenEditor(line.text)
	
	if not result then return end
	-- Replace line break with \N
	text = utf8.gsub(text, '\n', "\\N")
	line.text = text
	subs[selected[1]] = line

	aegisub.set_undo_point(show_rtl_editor_script_name)
end

--------------------------- Unify Background lines ------------------------------

function UnifyBackgroundLines(subs, selected)
	
	local firstLine, firstLineIdx = getFirstSubtitleLine(subs)
	if not isBackgroundLine(firstLine) then return end
	-- start processing lines
	local i, n = 0
	n = subs.n
	local lastBackgroundIdx = firstLineIdx;

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

	local code = GetTextFromUser()
	if code == nil then return end
	for i = 1, #selected, 1 do
		local line = subs[selected[i]]
		line.text = code..line.text
		subs[selected[i]] = line
	end
	aegisub.set_undo_point(add_code_to_selected_lines_script_name)
end

--------------------------- Remove line Breaks ------------------------------
function RemoveLineBreaks(subs, selected)
	
	if #selected > 1 then return end
	local line = subs[selected[1]]
	line.text = utf8.gsub(line.text, "\\N", " ")
	subs[selected[1]] = line

	aegisub.set_undo_point(remove_line_break_script_name)
end

---------------------- Import Text to selected lines -------------------------
function ImportTextToSelectedLines(subs, selected)
	
	if #selected == 0 then return end
	local result, text = OpenEditor("")
	
	if not result then return end
	local texts = text:split("\n")
	for i = 1, #selected, 1 do
		if i > table.getn(texts) then return end
		local line = subs[selected[i]]
		line.text = texts[i]
		subs[selected[i]] = line
	end

	aegisub.set_undo_point(import_text_to_selected_lines)
end	

------------------------- End of Main Methods -------------------

-- <<<<<<<<<<<<<<<<<<<<< Related Methods >>>>>>>>>>>>>>>>>>>>>>>>

---------------------- AddBackground Methods ------------------

function generateBackground(subs, styles, line, bgShape)
	local bgLine = table.copy(line)
	local lineCount = calcLineCount(line, styles)
	local lineHeight = getTextHeight(styles, line)

	local topAndBottomMargin = getTopAndBottomMargin(bgShape, lineHeight)
	local bgHeight = lineCount * lineHeight + topAndBottomMargin
	local repl = string.format("%%1%d%%3%d%%5", bgHeight, bgHeight)
	bgLine.text = bgShape.text:gsub(bgTransformPattern, repl)
	local r, i = string.gsub(bgShape.text, bgTransformPattern, repl)
	if i > 0 then
		bgLine.text = r
		bgLine.style = bgShape.style
		return bgLine
	end
	bgLine.text = "Error"
	return bgLine
end

function calcLineCount(line, styles)
	local text = line.text
	local videoWidth = getVideoWidth()
	local lineCount = 0;
	if text:match([[\N]]) ~= nil then
		local l = table.copy(line)
		local lineParts = text:split([[\N]])
		for i, t in ipairs(lineParts) do
			l.text = t
			lineCount = lineCount + getNoneBreakedLineCount(l, videoWidth, styles);
		end
	else
		lineCount = getNoneBreakedLineCount(line, videoWidth, styles)
	end
	return lineCount;
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
		ShowMessage(
tr[[The background shape is missing and now added as first line of subtitle.
Please use flowing steps:
   1- Uncomment background line.
   2- Align background shape with single line of subtitle.
   3- Use appropriate style for background.
   4- Recomment background line.
   5- Run command again.]])
		return nil, true
	end
	
	return firstLine, false, i
end

function getFirstSubtitleLine(subs)
	for i,l in ipairs(subs) do
		if l.class == 'dialogue' then
			l.i = i
			return l, i
		end
	end
	return nil, -1
end

function getTopAndBottomMargin(bgShape, lineHeight)
	local bgShapeHeight = string.gsub(bgShape.text, bgTransformPattern, "%2")
	return bgShapeHeight - lineHeight;
end

function string:split( inSplitPattern, outResults )
 
	if not outResults then
		outResults = {}
	end
	local theStart = 1
	local theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
	while theSplitStart do
		table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
	end
	table.insert( outResults, string.sub( self, theStart ) )
	return outResults
end

function isStartTimeEqualsPeriorEndTime(line, periorEndTime)
	if periorEndTime == "" then return false end
	local diff = line.start_time - periorEndTime
	-- < 2 Second
	return diff < 2000
end

function setLastGroupBackgroundEndTime(subs, groupBackgroundIndex, periorEndTime)
	if groupBackgroundIndex == -1 then return end
	local line = subs[groupBackgroundIndex]
	line.end_time = periorEndTime
	subs[groupBackgroundIndex] = line
end

function createBackgroundStyle(subs, styles)
	if styles["TextBackground"] then return end
	local style = {
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
		align = 2,
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
	bgLine.comment = true
	bgLine.style = "TextBackground"
	bgLine.text = string.format("{\\p1\\pos(%d,%d)}m 0 0 l %d 0 l %d %d l 0 %d l 0 0", videoW/2, videoH-margin, videoW-margin*2, videoW-margin*2, margin*4, margin*4)
	subs.insert(idx, bgLine)
end

function cleanTags(text)
	return string.gsub(text, [[{\.-}]], "")
end

function isBackgroundLine(line)
	return string.match(line.text, bgPattern) ~= nil
end

function ShowMessage(msg)
	config = {
		{class="label", label="\r\n" .. msg .. "\r\n", x=0, y=0}
	}
	btn, result = aegisub.dialog.display(config, {"OK"}, {ok="OK"})
end

function videoLoaded()
	w = getVideoWidth()
	if w == nil then
		ShowMessage(
[[There is no loaded video. 
Please "Open Video..." or "Use Dummy Video..." and try again.]])
		return false
	end
	return true
end

function mayAddBackground(line)
	return (not string.find(line.style:lower(), "_nobg")) and (not string.find(line.text, "\\nobg")) or (string.find(line.style:lower(), "_nobg") and (string.find(line.text, "\\addbg")))
end
--------------------- SplitLine Methods ----------------------------

function GetFirstChar(text, chars)
	local sStart = string.len(text)
	local sEnd = 0
	local idx = 0
	for i = 1, #chars do
		local s, e = string.find(text, chars[i])
		if s ~= nil and s < sStart then 
			sStart = s 
			sEnd = e
			idx = i
		end
	end
	return sStart, sEnd, idx
end

function ChangeLineTime(text, line1, line2)
	start=line1.start_time
	endt=line1.end_time
	dur=endt-start
	--aegisub.log(dur)
	l=dur/string.len(text)
	line1.end_time = start + string.len(line1.text)*l
	line2.start_time = line1.end_time
	return line1, line2
end

function GetIndexFromUser()
	config = {
		{class="label", label="\r\n Enter index of character that you want to split line on that character: \r\n", x=0, y=0},
		{class="intedit", name="charIndex", value=2, x=0, y=1}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok="OK", cancel="Cancel"})
	if btn then	
		local r = tonumber(result.charIndex)
		return r
	end
	return 0
end

function compare(a,b)
  return a[1] < b[1]
end

function GetCharAtIndex(text, index)
  local parts = {}
	local idx = 0
  
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
  
  if #parts > 0 then 

  	if index > #parts then return nil end
    -- returns start, end, SplitCharIndex
    return parts[index][1], parts[index][2], parts[index][3]
  end
	return nil
end

function GetTextFromUser()
	config = {
		{class="label", label="\r\n Enter your code here: \r\n", x=0, y=0},
		{class="textbox", name="txtCode", value="{\\ }", x=0, y=1, width=10}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok="OK", cancel="Cancel"})
	if btn then
		return result.txtCode
	end
	return nil
end

----------------------- RtlCorrection Methods ---------------------

function RemoveRle(s)
	local rleChar = utf8.char(0x202B)

	local replaced = utf8.gsub(s, rleChar, "")
	return replaced
end

function AddRleToEachNoneAlphabeticChars(s)
	local pattern = "([{"..SpecialChars.."}])"

	-- Start of right to left embeding character
	local rleChar = utf8.char(0x202B)

	local replaced = utf8.gsub(s, pattern, rleChar.."%1")
	replaced = utf8.gsub(replaced, "\\N", "\\N"..rleChar)
    return rleChar..replaced
end

function RemoveDoubleSpace(s)
	while string.match(s, "%s%s") ~= nil do
		s = string.gsub(s, "%s%s", " ")
	end
	return s
end

function RemoveSpacesBeforePunctuationMarks(s)
	local pattern = "(%s\"+)([{"..PunctuationMarks.."}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%2")
	end
	return replaced
end

function AddRequiredSpaceAfterPunctuationMarks(s)
	local pattern = "([{"..PunctuationMarks.."}])([^%s{"..PunctuationMarks.."}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function AddRequiredSpaceAfterPunctuationMarks(s)
	local pattern = "([{"..PunctuationMarks.."}])([^%s{"..PunctuationMarks.."}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function RemoveSpaceAfterStartingBrackets(s)
	local pattern = "([{"..StartingBracketChars.."}])([%s]+)"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1")
	end
	return replaced
end

function RemoveSpaceBeforeEndingBrackets(s)
	local pattern = "([%s]+)([{"..EndingsBracketChars.."}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%2")
	end
	return replaced
end

function AddRequiredSpaceAfterEndingBrackets(s)
	local pattern = "([{"..EndingsBracketChars.."}])([^%s{"..EndingsBracketChars..PunctuationMarks..StartingBracketChars.."\"}])"
	local replaced = s
	if utf8.match(replaced, pattern) then
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function AddRequiredSpaceBeforeStartingBrackets(s)
	local pattern = "([^%s{"..StartingBracketChars.."}])([{"..StartingBracketChars.."}])"
	local replaced = s
	while utf8.match(replaced, pattern) do
		replaced = utf8.gsub(replaced, pattern, "%1 %2")
	end
	return replaced
end

function Trim(s)
  local r = s:gsub("^%s*(.-)%s*$", "%1")
  return r
end

function IsRtl(s)
	local RtlChars = {"ء", "آ", "أ", "ا", "ب", "پ", "ت", "ة", "ث", "ج", "چ", "ح", "خ", "د", "ذ", "ر", "ز", "ژ", "س", "ش", "ص", "ض", "ط", "ظ", "ع", "غ", "ف", "ق", "ک", "ك", "گ", "ل", "م", "ن", "و", "ه", "ی", "ي"}
	
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

function GetTextParts(s)
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
  
    if string.len(text) > 0 then
      table.insert(parts, text)
    end  
  
  return parts
end

------------------------------- Rtl Editor Methods ----------------------

function OpenEditor(str)
	config = {
		{class="label", label="\r\n Press Ctrl+Shift to switch to Right to left mode \r\n", x=0, y=0},
		{class="textbox", name="editor", value=str, x=0, y=1, width=12, height=8}
	}
	btn, result = aegisub.dialog.display(config, {"OK", "Cancel"}, {ok="OK", cancel="Cancel"})
	return btn, result.editor
end

aegisub.register_macro(add_selected_background_script_name, tr"Adds background for selected line", AddSelectedBackground)
aegisub.register_macro(add_background_script_name, tr"Adds background before every line", AddBackground)
aegisub.register_macro(split_script_name, tr"Split selected lines", Split)
aegisub.register_macro(split_at_index_script_name, tr"Split selected line at index", SplitAtIndex)
aegisub.register_macro(rtl_correction_script_name, tr"Corercts Rtl display problem for all line", RtlCorrection)
aegisub.register_macro(rtl_correction_selected_line_script_name, tr"Corercts Rtl display problem for selected line", RtlCorrectorSelectedLine)
aegisub.register_macro(undo_rtl_correction_script_name, tr"Undo Rtl correction", UndoRtlCorrection)
aegisub.register_macro(show_rtl_editor_script_name, tr"Show Rtl editor", ShowRtlEditor)
aegisub.register_macro(unify_background_lines_script_name, tr"Unify Background Lines", UnifyBackgroundLines)
aegisub.register_macro(add_code_to_selected_lines_script_name, tr"Add Code To Selected Lines", AddCodeToSelectedLines)
aegisub.register_macro(remove_line_break_script_name, tr"Remove line Breaks", RemoveLineBreaks)
aegisub.register_macro(import_text_to_selected_lines, tr"Import text to selected lines", ImportTextToSelectedLines)
