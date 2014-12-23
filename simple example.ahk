; Simplest usage example.
; Minimal error checking (Just check if DLL loaded), just the bare essentials code-wise.

#SingleInstance, force
#include CvJoyInterface.ahk

; Create an object from vJoy Interface Class.
vJoyInterface := new CvJoyInterface()

; Was vJoy installed and the DLL Loaded?
if (!vJoyInterface.vJoyEnabled()){
	; Show log of what happened
	Msgbox % vJoyInterface.LoadLibraryLog
	ExitApp
}

myStick := vJoyInterface.Devices[1]

; End Startup Sequence
Return

; Hotkeys
F11::
	; Refer to the stick by name, move it to 0%
	myStick.SetAxisByName(0,"x")
	SoundBeep
	return

F12::
	; Refer to the stick by index (axis number), move it to 100% (32768)
	myStick.SetAxisByIndex(vJoyInterface.PercentTovJoy(100),1)
	SoundBeep
	return