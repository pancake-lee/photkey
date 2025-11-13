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
		; Split line by comma into array-like variables
		parts := []
		Loop, Parse, line, `,
			parts.Push(A_LoopField)

		; ensure at least 7 parts
		Loop, % 7 - parts.Length()
			parts.Push("")

		shift := parts[1]
		ctrl := parts[2]
		alt := parts[3]
		trigger := parts[4]
		target := parts[5]
		name := parts[6]
		desc := parts[7]

		if (trigger = ""){
			continue
        }

		key := SubStr(trigger, 1, 1)
		key := TrimStr(key)
		key := ToLower(key)

		mappings[key] := {target: target, name: name, shift: shift, ctrl: ctrl, alt: alt}

	    Log("reg key mapping " trigger " -> " target)
	}
}

; 构建并显示键盘映射 GUI（使用 keyboardImgPath 和 keyboardPos/mappings）
BuildKeyboardGui()
{
	global keyboardImgPath, keyboardPos, mappings, tooltipDuration, keyboardGuiShown
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

	; 设置字体
	Gui, KeyboardGui: Font, s10, Segoe UI

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

        posX := pos.x / 1.5
        posY := pos.y / 1.5

		; 限制文本宽度与高度，可根据需要调整
		Gui, KeyboardGui: Add, Text, x%posX% y%posY% w60 h20 +Center +BackgroundTrans, %text%
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

SetCapsLockState, Off
hyperActive := False

; 载入映射
LoadMappings()

Log("load config done")

; 目前为 a-z 和 0-9 注册热键(初始目标为字母和数字)。
; 这样可以避免对标点等特殊字符热键名的复杂转义。
chars := "abcdefghijklmnopqrstuvwxyz0123456789"
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
	ShowToast(modifiers)
    Log("map " key " -> " modifiers map.target)

	; 发送目标键:保留修饰符,只替换基础键
	if (map.target != "")
	{
		targetKey := map.target
		; 如果目标是单字符(字母或数字),直接发送
		if RegExMatch(targetKey, "^[A-Za-z0-9]$")
		{
			; 保留修饰符,发送 修饰符+目标键
			SendInput, % modifiers . targetKey
		}
		else
		{
			; 特殊键(如 Left、Up、Enter),用大括号包裹,并保留修饰符
			SendInput, % modifiers . "{" . targetKey . "}"
		}
	}
Return

RemoveTooltip:
	ToolTip
Return
