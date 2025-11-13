; photkey.ahk
; AHK v1 脚本，实现一个简单的 HyperKey（使用 CapsLock）。
; - 从 %UserProfile%\photkey\photkey.conf 读取映射（CSV 风格，逗号分隔）。
; - 在 HyperKey 激活时，拦截可打印键（字母、数字、标点），并根据配置重映射到目标 AHK 键；若有映射则发送目标键。
; - 显示短暂提示（ToolTip）以显示映射名称或相关信息。
; - 若无映射，则短暂显示“无影射快捷键”。
;
; 说明：
; - 脚本针对 AutoHotkey v1 编写。
; - 配置格式（每行一条映射，逗号分隔）：
;   shift,ctrl,alt,trigger_key,target_ahk_key,name,description
;   示例： ,,,i,Up,ArrowUp,
; - 为简单起见，脚本在启动时读取一次配置。

; --------------------------------------------------
; 函数定义
; --------------------------------------------------

; 简单日志函数:将时间戳与 msg 写入日志文件
Log(msg)
{
	global logPath
	FormatTime, t, %A_Now%, yyyy-MM-dd HH:mm:ss
	FileAppend, % t " - " msg "`n", %logPath%
}
; Helper: show transient tooltip centered near mouse
ShowToast(text)
{
	global tooltipDuration
	ToolTip, %text%
	SetTimer, RemoveTooltip, -%tooltipDuration%
}

; 获取主显示器 DPI 缩放倍率 (AHK v1)
; 返回值示例: 1.0 (100%), 1.25 (125%), 2.0 (200%)
GetDpiScale_AhkV1()
{
	; 尝试使用 Shcore.dll 的 GetDpiForMonitor (Windows 8.1+)
	; MonitorFromPoint 返回 HMONITOR
	VarSetCapacity(mi, 40, 0)
	hMon := DllCall("MonitorFromPoint", "int64", 0, "uint", 2, "ptr")
	dpiX := 96
	dpiY := 96
	; 默认回退为系统 DPI (A_ScreenDPI)
	sysDpi := A_ScreenDPI
	ret := 1.0
	; 尝试调用 GetDpiForMonitor (Windows 8.1+)
	h := DllCall("LoadLibrary", "Str", "Shcore.dll")
	if (h != 0)
	{
		; typedef HRESULT GetDpiForMonitor(HMONITOR, MONITOR_DPI_TYPE, UINT*, UINT*);
		; MONITOR_DPI_TYPE 0 = MDT_EFFECTIVE_DPI
		if (DllCall("Shcore.dll\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", dpiX, "uint*", dpiY) = 0)
		{
			ret := dpiX / 96.0
			DllCall("FreeLibrary", "ptr", h)
			goto done
		}
		DllCall("FreeLibrary", "ptr", h)
	}

	; 如果不存在 Shcore 或调用失败，尝试使用 GetDeviceCaps
	hDC := DllCall("GetDC", "uint", 0, "ptr")
	if (hDC)
	{
		; LOGPIXELSX = 88
		dpiX := DllCall("gdi32.dll\GetDeviceCaps", "ptr", hDC, "int", 88)
		DllCall("ReleaseDC", "uint", 0, "ptr", hDC)
		if (dpiX && dpiX > 0)
			ret := dpiX / 96.0
	}

done:
	; 确保返回至少 1.0
	if (ret < 1.0)
		ret := 1.0
	return ret
}

; Helper: trim whitespace and lowercase for AHK v1 compatibility
TrimStr(s)
{
	if (s = ""){
		return ""
    }
	return RegExReplace(s, "^\s+|\s+$")
}

ToLower(s)
{
	tmp := s
	StringLower, tmp, tmp
	return tmp
}

; Read config file into mappings object (AHK v1 compatible)
LoadMappings()
{
	global confPath, mappings
	mappings := {}
	if !FileExist(confPath)
	{
		Log("conf not found: " confPath)
		return
	}

	FileRead, content, %confPath%
	if ErrorLevel
	{
		Log("conf not found: " confPath)
		return
	}

	; Normalize line endings and iterate lines
	StringReplace, content, content, `r`n, `n`, All ; 有点问题，CRLF会丢配置
	StringReplace, content, content, `r`, `n`, All

	Loop, Parse, content, `n`
	{
		line := A_LoopField
		if (line = ""){
			continue
        }
        ; Log("loading : " line)

		; Split line by comma into array-like variables
		parts := []
		Loop, Parse, line, `,
			parts.Push(A_LoopField)

		; 恢复占位符为真实逗号（先读到临时变量，替换后写回）
		Loop, % parts.Length()
		{
			idx := A_Index
            if (parts[idx] = "COMMA"){
                ; Log("loading parts found [" idx "] = " parts[idx])
                parts[idx] := ","
            }

            ; Log("loading parts [" idx "] = " parts[idx])
		}

		; ensure at least 8 parts (新增 color 列：shift,ctrl,alt,trigger,target,name,color,desc)
		Loop, % 8 - parts.Length()
			parts.Push("")

		shift := parts[1]
		ctrl := parts[2]
		alt := parts[3]
		trigger := parts[4]
		target := parts[5]
		name := parts[6]
		color := parts[7]
		desc := parts[8]

		if (trigger = ""){
			continue
        }

		key := SubStr(trigger, 1, 1)
		key := TrimStr(key)
		key := ToLower(key)

		mappings[key] := {target: target, name: name, color: color, shift: shift, ctrl: ctrl, alt: alt}

	    Log("reg key mapping " trigger " -> " target)
	}
}

; 构建并显示键盘映射 GUI（使用 keyboardImgPath 和 keyboardPos/mappings）
BuildKeyboardGui()
{
	global keyboardImgPath, keyboardPos, mappings, tooltipDuration, keyboardGuiShown, colorMap, defaultColor, detectedScale
	if !FileExist(keyboardImgPath)
	{
		ShowToast("keyboard image not found")
		Return
	}

	; 先销毁已有 GUI（如果有）
	Gui, KeyboardGui: Destroy

	; 创建无标题浮动窗口，图片为背景
	Gui, KeyboardGui: +AlwaysOnTop -Caption +ToolWindow
	Gui, KeyboardGui: Add, Picture, x0 y0, %keyboardImgPath%

	; 设置字体（加粗）
	Gui, KeyboardGui: Font, s10 Bold, Segoe UI

	; 在对应位置渲染映射名称（优先 name，否则使用 target）
	for key, map in mappings
	{
		pos := keyboardPos[key]
		if !IsObject(pos){
			continue
        }

		text := map.name
		if (text = ""){
			text := map.target
        }

	; 根据系统 DPI 缩放系数调整坐标
	posX := pos.x / detectedScale
	posY := pos.y / detectedScale

		; 颜色解析：优先使用映射中的 color 字段
		col := map.color
		if (col = ""){
			col := defaultColor
        }else{
			; 支持颜色名或直接 hex（去除可能的 #）
			StringTrimLeft, tmp, col, 0
			StringReplace, tmp, tmp, "#", "", All
			; 若是名称映射，替换为 hex
			if (colorMap.HasKey(ToLower(col))){
				tmp := colorMap[ToLower(col)]
            }
            ; Log("color : " col " hex : " tmp)
		}

		; 限制文本宽度与高度，可根据需要调整；使用 c<hex> 设置颜色
		Gui, KeyboardGui: Add, Text, x%posX% y%posY% w60 h20 +Center +BackgroundTrans c%tmp%, %text%
	}

	Gui, KeyboardGui: Show
	keyboardGuiShown := true
}

Log("mark func def done")

; --------------------------------------------------
; 主程序

; 确保 AppData 下的 photkey 目录存在，并定义日志/配置路径
appDataDir := A_AppData "\..\..\photkey\"
if !FileExist(appDataDir)
{
	FileCreateDir, %appDataDir%
}
logPath := appDataDir "photkey.log"
confPath := appDataDir "photkey.conf"

mappings := {}
tooltipDuration := 3000 ; ms

; 颜色映射（名称 -> 十六进制 RGB，无 #）
colorMap := {"red":"E61C5D", "green":"99CC33", "blue":"00BBF0", "yellow":"FFBD39", "black":"000000", "pink":"E6A4B4"}
defaultColor := "FFFFFF"

SetCapsLockState, Off
hyperActive := False

; 载入映射
LoadMappings()

Log("load config done")

; 检测系统缩放（DPI）并记录，用于 GUI 渲染等处
detectedScale := GetDpiScale_AhkV1()
Log("detected DPI scale: " detectedScale)

; 目前为 a-z 和 0-9 注册热键(初始目标为字母和数字)。
; 这样可以避免对标点等特殊字符热键名的复杂转义。
; 包括字母、数字与常用符号（支持 - = [ ] \ ; ' , . / 和 `）
chars := "abcdefghijklmnopqrstuvwxyz0123456789`-=[]\;',./"
; chars := "j"
; 修饰键组合列表(* 通配符在 Hotkey 命令中不起作用,需要显式注册)
modifiers := ["", "+", "^", "!", "+^", "+!", "^!", "+^!"]
Loop, Parse, chars
{
	ch := A_LoopField
	; 使用 $ 前缀防止热键触发自身
	; 为每个字符注册所有修饰键组合
	for index, mod in modifiers
	{
		hk := "$" . mod . ch
		Hotkey, %hk%, HandlePrintable, On
	}
    ; Log("reg chars key " ch)
}

; --------------------------------------------------
; 实现F1唤出快捷键映射图
keyboardImgPath := appDataDir "keyboard.jpeg"
keyboardVec := [["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"],["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"]]
keyboardStartPos:=[{x:32, y:17},{x:240, y:140},{x:267, y:263},{x:330, y:386}]
keyboardInterval := 128
keyboardPos := {}

keyboardGuiShown := false ; GUI 控制状态

; 初始化 keyboardPos：
; 对于 keyboardVec 的每一行，使用 keyboardStartPos 对应元素作为起点，
; 行内第一个键的坐标等于起点，后续键的 x 坐标按 keyboardInterval 递增。
Loop, % keyboardVec.Length()
{
	rowIndex := A_Index
	row := keyboardVec[rowIndex]
	start := keyboardStartPos[rowIndex]

	Loop, % row.Length()
	{
		col := A_Index
		key := row[col]
		; 计算坐标
		posX := start.x + (col - 1) * keyboardInterval
		posY := start.y
		keyLower := ToLower(key)
		keyboardPos[keyLower] := {x: posX, y: posY}
	}
}
; --------------------------------------------------
Log("Everything is ready.")

; --------------------------------------------------
;   
; 使用 CapsLock 作为 HyperKey 切换
; 保持 CapsLock 指示灯用于显示 HyperKey 状态
CapsLock::
	hyperActive := !hyperActive
	if (hyperActive)
	{
		SetCapsLockState, On
		ShowToast("HyperKey ON")
	}
	else
	{
		SetCapsLockState, Off
		ShowToast("HyperKey OFF")
        
        if (keyboardGuiShown)
        {
            Gui, KeyboardGui: Destroy
            keyboardGuiShown := false
        }
	}
Return

; Hyper + F1: 切换键盘映射面板
$F1::
	if !hyperActive
	{
		SendInput, {F1}
		Return
	}

	if (!keyboardGuiShown)
	{
		BuildKeyboardGui()
	}
	else
	{
		Gui, KeyboardGui: Destroy
		keyboardGuiShown := false
	}
Return

; Esc: 如果键盘 GUI 打开则关闭它，否则发送普通 Esc
$Esc::
	if !hyperActive
	{
		SendInput, {Esc}
		Return
	}

	if (keyboardGuiShown)
	{
		Gui, KeyboardGui: Destroy
		keyboardGuiShown := false
		Return
	}
	; 否则传递普通 Esc
	SendInput, {Esc}
Return



; --------------------------------------------------
; 标签定义

; 可打印键的处理函数
HandlePrintable:
	; 获取按下的热键名(A_ThisHotkey)作为按键标识
	key := A_ThisHotkey
	; 移除 $ 前缀
	key := StrReplace(key, "$")
	; 提取修饰符前缀(+^!)
	modifiers := RegExReplace(key, "[^+^!].*$", "")
    ; 提取实际按键(去除修饰符)
	actualKey := RegExReplace(key, "^[+^!]*", "")
	
    ; 未处于 HyperKey 状态:直接发送原始按键，包含修饰符
	if !hyperActive
	{
    	; Log("origin " key)
		SendInput, {Blind}%actualKey%
		Return
	}

	; 处于 HyperKey:检查映射(忽略修饰符,只看实际按键)
	k := ToLower(actualKey)
	if (mappings[k] = "")
	{
    	Log("unmap " actualKey)
		ShowToast("unmap " actualKey)
		Return
	}

	map := mappings[k]
	targetKey := map.target

	; 如果 targetKey 自身包含修饰符前缀（+^! 之一或组合），且这些修饰符
	; 已出现在当前按下的 modifiers 中，则从 targetKey 前缀中移除重复项，
	; 避免发送时重复修饰符。例如: modifiers="^" 且 targetKey = "^s" -> targetKey="s"
	if (targetKey != "")
	{
		; 提取 targetKey 的修饰符前缀
		targetMods := RegExReplace(targetKey, "[^+^!].*$", "")
		; 如果都为空则无修饰符
		if (targetMods != "")
		{
			; 对每个可能的修饰符进行检查，如果 modifiers 已包含该修饰符，则从 targetMods 中移除
			; 注意 AHK 中修饰符表示: + (Shift), ^ (Ctrl), ! (Alt)
			newTargetMods := targetMods
			if (InStr(modifiers, "+") && InStr(newTargetMods, "+"))
				StringReplace, newTargetMods, newTargetMods, +, , All
			if (InStr(modifiers, "^") && InStr(newTargetMods, "^"))
				StringReplace, newTargetMods, newTargetMods, ^, , All
			if (InStr(modifiers, "!") && InStr(newTargetMods, "!"))
				StringReplace, newTargetMods, newTargetMods, !, , All

			; 将处理后的修饰符拼回 targetKey 的主体
			if (newTargetMods != targetMods)
			{
				; 移除原前缀后拼接剩余部分
				baseKey := RegExReplace(targetKey, "^[+^!]*", "")
				targetKey := newTargetMods . baseKey
				; Log("dedup modifiers, new targetKey=" targetKey)
			}
		}

        Log("input " key " -> " modifiers targetKey)
        ShowToast(modifiers targetKey)

		; 发送目标键:保留修饰符,只替换基础键
		if RegExMatch(targetKey, "^[A-Za-z0-9``\-\=\[\]\\;',\./]$")
		{
			SendInput, % modifiers . targetKey
		}
		else
		{
			SendInput, % modifiers . "{" . targetKey . "}"
		}
	}
Return

RemoveTooltip:
	ToolTip
Return
