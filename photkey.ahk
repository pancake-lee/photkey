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

/*
关于“每监视器 DPI 感知”及其API：SetThreadDpiAwarenessContext
https://wyagd001.github.io/zh-cn/docs/misc/DPIScaling.htm
https://learn.microsoft.com/zh-cn/windows/win32/api/winuser/nf-winuser-setthreaddpiawarenesscontext#parameters
https://learn.microsoft.com/zh-cn/windows/win32/hidpi/dpi-awareness-context
简单总结
    1：-3/-4 开启每监视器 DPI 感知
    2：ahk官网文档：启用每监视器 DPI 感知将禁用系统执行的缩放, 因此诸如 WinMove 和 WinGetPos 之类的命令将接受或返回像素坐标, 不受 DPI 缩放的影响. 然而, 如果一个 GUI 的大小适合于 100 % DPI 的屏幕, 然后移动到 200 % DPI 的屏幕, 它将不会自动调整, 并且可能会非常难以使用.
    3：个人总结，设置了-3后，后续xywh的数值直接根据像素来计算，不用考虑DPI缩放了

以上说的是“显示器的缩放比例”，但系统依然有一个缩放比例，见下面两个文档
https://wyagd001.github.io/zh-cn/docs/Variables.htm#ScreenDPI
https://wyagd001.github.io/zh-cn/docs/lib/Gui.htm#DPIScale
系统缩放比例=A_ScreenDPI/96，在我的2K屏幕中是144/96=1.5

而在上面DPIScale文档里面，提到Gui -DPIScale选项
https://wyagd001.github.io/zh-cn/docs/lib/Gui.htm#WindowOptions
关闭这个选项后，则系统缩放比例也不会生效了

然后我们可以完全用屏幕像素来计算坐标和尺寸，而不必担心 DPI 缩放的影响。
我的目标是准确定位80%的屏幕宽度，等比缩放图像，展示在屏幕中央。
*/

EnsureProcessDpiAwareness()
{
   
    ; 但仍需要根据系统显示进行缩放，则 A_ScreenDPI/96，在我的2K屏幕中是144/96=1.5
    ; https://wyagd001.github.io/zh-cn/docs/lib/Gui.htm#DPIScale
    DPI_AWARENESS_CONTEXT := -3
	resCtx := 0
	; 注意：如果函数不存在，DllCall 会设置 ErrorLevel
	resCtx := DllCall("user32.dll\SetThreadDpiAwarenessContext", "ptr", DPI_AWARENESS_CONTEXT)
	if ErrorLevel
	{
		Log("SetThreadDpiAwarenessContext[" DPI_AWARENESS_CONTEXT "] failed: " ErrorLevel)
	}
	else
	{
		Log("SetThreadDpiAwarenessContext[" DPI_AWARENESS_CONTEXT "] succeeded")
	}
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
	; 先销毁已有 GUI（如果有）
	CloseKeyboardGui()

	global keyboardImgPath, keyboardPos, mappings, tooltipDuration, keyboardGuiShown, colorMap, defaultColor, keyboardKeyW, overlayShown

	if !FileExist(keyboardImgPath)
	{
		ShowToast("keyboard image not found")
		Return
	}

	; 创建并显示遮罩 OverlayGui（带 hwnd 以便精确设置透明度）
	Gui, OverlayGui: -Caption +ToolWindow -DPIScale +HwndhOverlay
	Gui, OverlayGui: Color, 000000
	Gui, OverlayGui: Show, NoActivate x%monLeft% y%monTop% w%monWidth% h%monHeight%
	; 使用 hOverlay 精确设置透明度
	if (hOverlay)
		WinSet, Transparent, 200, ahk_id %hOverlay%
	overlayShown := true

    ; 获取主显示器索引和值（MonitorPrimary 返回主显示器编号）
    SysGet, primIndex, MonitorPrimary
    targetMonIndex := primIndex
    ; 读取主显示器的工作区到 primLeft/primTop/primRight/primBottom
    SysGet, prim, MonitorWorkArea, %primIndex%
    ; Log("primary monitor[" primIndex "] work area [" primLeft "," primTop "," primRight "," primBottom "]")

	; 获取监视器数量并选择目标监视器（优先第二屏，有则用 2，否则用 1）
	SysGet, monCount, MonitorCount
	if (monCount >= 2)
	{
		; 获取鼠标位置，判断鼠标是否在主显示器工作区内
        CoordMode, Mouse, Screen
		MouseGetPos, mx, my
        ; Log("mouse pos: " mx "x" my)
		if (mx >= primLeft && mx <= primRight && my >= primTop && my <= primBottom)
		{
			; 鼠标在主屏上，若存在第二屏则使用第二屏，还要考虑主屏不是1的情况
            if primIndex = 1
                targetMonIndex := 2
            else
                targetMonIndex := 1

			SysGet, mon, MonitorWorkArea, %targetMonIndex%
		}
		else
		{
			; 鼠标不在主屏，使用主屏
			monLeft := primLeft
			monTop := primTop
			monRight := primRight
			monBottom := primBottom
		}
	}
	else
	{
        ; 只有一块显示器，使用主屏
        monLeft := primLeft
        monTop := primTop
        monRight := primRight
        monBottom := primBottom
	}

    ; 显示原始大小
    origW := 1920
    origH := 500

	; 目标宽度为目标显示器工作区宽的 80%
	monWidth := monRight - monLeft
    monHeight := monBottom - monTop
    Log("monitor[" targetMonIndex "] work area [" monLeft "," monTop "," monRight "," monBottom "] " monWidth "x" monHeight)

	targetW := Round(monWidth * 0.8)
	scale := targetW / origW
	targetH := Round(origH * scale)
    frontSize := 10 * scale
    ; Log("target size: " targetW "x" targetH)

	; 重新创建 GUI，使用指定的宽高来缩放图片，并按比例缩放文本坐标
	Gui, KeyboardGui: +AlwaysOnTop -Caption +ToolWindow -DPIScale
	Gui, KeyboardGui: +HwndhGui ; 创建了名为 hGui 的变量
	Gui, KeyboardGui: Add, Picture, x0 y0 w%targetW% h%targetH%, %keyboardImgPath%
	Gui, KeyboardGui: Font, s%frontSize% Bold, Segoe UI Black

	; 在对应位置渲染映射名称（优先 name，否则使用 target），坐标按 scale 缩放并考虑 DPI
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

		; 根据缩放系数调整坐标
		posX := Round(pos.x * scale)
		posY := Round(pos.y * scale)

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
		}

        posX := posX + keyboardKeyW * scale *0.05 ; 上边框距离5%
        posY := posY + keyboardKeyW * scale *0.05 ; 左边框距离5%
        textW := keyboardKeyW * scale * 0.9 ; 文字区域宽度90%
        textH := keyboardKeyW * scale * 0.3 ; 文字区域高度30%
		Gui, KeyboardGui: Add, Text, x%posX% y%posY% w%textW% h%textH% +Center +BackgroundTrans c%tmp%, %text%
	}

	; 将 GUI 居中在目标显示器（水平与垂直居中）
	newX := monLeft + Round((monRight - monLeft - targetW) / 2)
	newY := monTop + Round((monBottom - monTop - targetH) / 2)
    Log("target pos: [" newX "," newY "," newX+targetW "," newY+targetH "] front["  frontSize "] size: [" targetW "x" targetH "]")


	; NoActivate 避免抢焦点
	Gui, KeyboardGui: Show, NoActivate x%newX% y%newY% w%targetW% h%targetH%
	keyboardGuiShown := true
}

Log("mark func def done")

; 统一关闭键盘 GUI 与遮罩
CloseKeyboardGui()
{
	global keyboardGuiShown, overlayShown
	; 如果键盘 GUI 存在则销毁
	Gui, KeyboardGui: Destroy
	keyboardGuiShown := false

	; 销毁遮罩（若存在）
	if (overlayShown)
	{
		Gui, OverlayGui: Destroy
		overlayShown := false
	}
}

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

EnsureProcessDpiAwareness()

; 载入映射
LoadMappings()

Log("load config done")

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
keyboardInterval := 128 ; 两个按键间（左上到左上）的水平间距
keyboardKeyW := 90 ; 一个按键的宽度
keyboardPos := {}

keyboardGuiShown := false ; GUI 控制状态
overlayShown := false

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
		CloseKeyboardGui()
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
		CloseKeyboardGui()
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
		CloseKeyboardGui()
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
