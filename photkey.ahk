; photkey.ahk
; AHK v1 脚本，实现一个简单的 HyperKey（使用 CapsLock）。
; - 从 D:\nycko\code\photkey\photkey.conf 读取映射（CSV 风格，逗号分隔）。
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

; 日志输出路径(用于替换 TrayTip 调试输出)
logPath := A_AppData "\photkey\photkey.log"

; 简单日志函数:将时间戳与 msg 写入日志文件
Log(msg)
{
	global logPath
	FormatTime, t, %A_Now%, yyyy-MM-dd HH:mm:ss
	FileAppend, % t " - " msg "`n", %logPath%
}
; --------------------------------------------------
; 变量定义
confPath := A_AppData "\photkey\photkey.conf"
tooltipDuration := 3000 ; ms

; 映射表：key => 包含 target、name、shift/ctrl/alt 字段的对象
mappings := {}

; HyperKey 状态标志
hyperActive := false

Log("mark var def done")
; --------------------------------------------------
; 函数定义
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
	if (s = "")
		return ""
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
		Log("配置文件未找到: " confPath)
		return
	}

	FileRead, content, %confPath%
	if ErrorLevel
	{
		Log("无法读取配置文件: " confPath)
		return
	}

	; Normalize line endings and iterate lines
	StringReplace, content, content, `r`n, `n`, All
	StringReplace, content, content, `r`, `n`, All

	Loop, Parse, content, `n`
	{
		line := A_LoopField
		if (line = "")
			continue

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

		if (trigger = "")
			continue

		key := SubStr(trigger, 1, 1)
		key := TrimStr(key)
		key := ToLower(key)

		mappings[key] := {target: target, name: name, shift: shift, ctrl: ctrl, alt: alt}

	    Log(name)
	}
}

Log("mark func def done")
; --------------------------------------------------
; 主程序

; 初始化设置
SetCapsLockState, AlwaysOff  ; 禁用 CapsLock 的大写锁定功能
hyperActive := false          ; 确保 HyperKey 初始状态为关闭

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
Log("reg chars keys done")

; --------------------------------------------------
;   
; 使用 CapsLock 作为 HyperKey 切换
CapsLock::
	hyperActive := !hyperActive
	if (hyperActive)
		ShowToast("HyperKey ON")
	else
		ShowToast("HyperKey OFF")
	Return

; 使用 Ctrl+Alt+R 重载脚本
^!r::
	Reload
Return

; 使用 Ctrl+Alt+Q 退出脚本
^!q::ExitApp

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
	
	if !hyperActive
	{
		; 未处于 HyperKey 状态:直接发送原始按键(包含修饰符)
    	Log("origin " key)
		SendInput, %key%
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
