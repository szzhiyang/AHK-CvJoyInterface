
Class CvJoyInterface {
	DebugMode := 0
	LibraryLoaded := 0
	LoadLibraryLog := ""
	hModule := 0
	Devices := []

	VJD_MAXDEV := 16
 
	; ported from VjdStat in vjoyinterface.h
	VJD_STAT_OWN := 0   ; The  vJoy Device is owned by this application.
	VJD_STAT_FREE := 1  ; The  vJoy Device is NOT owned by any application (including this one).
	VJD_STAT_BUSY := 2  ; The  vJoy Device is owned by another application. It cannot be acquired by this application.
	VJD_STAT_MISS := 3  ; The  vJoy Device is missing. It either does not exist or the driver is down.
	VJD_STAT_UNKN := 4  ; Unknown
 
	; HID Descriptor definitions(ported from public.h
	HID_USAGE_X := 0x30
	HID_USAGE_Y := 0x31
	HID_USAGE_Z := 0x32
	HID_USAGE_RX:= 0x33
	HID_USAGE_RY:= 0x34
	HID_USAGE_RZ:= 0x35
	HID_USAGE_SL0:= 0x36
	HID_USAGE_SL1:= 0x37

	AxisIndex := [0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37]
	AxisAssoc := {x:0x30, y:0x31, z:0x32, rx:0x33, ry:0x34, rz: 0x35, sl1:0x36, sl2:0x37}

	; ===== Device helper subclass.
	Class CvJoyDevice {
		IsOwned := 0

		__New(id, parent){
			this.DeviceID := id
			this.Interface := parent
		}

		__Delete(){
			this.Relinquish()
		}

		GetStatus(){
			return this.Interface.GetVJDStatus(this.DeviceID)
		}

		; Converts Status to human readable form
		GetStatusName(){
			DeviceStatus := this.GetStatus()
			if (DeviceStatus = this.Interface.VJD_STAT_OWN) {
				return "OWN"
			} else if (DeviceStatus = this.Interface.VJD_STAT_FREE) {
				return "FREE"
			} else if (DeviceStatus = this.Interface.VJD_STAT_BUSY) {
				return "BUSY"
			} else if (DeviceStatus = this.Interface.VJD_STAT_MISS) {
				return "MISS"
			} else {
				return "???"
			}
		}

		; Acquire the device
		Acquire(){
			ret := this.Interface.AcquireVJD(this.DeviceID)
			if (!ret && this.Interface.DebugMode){
				OutputDebug, % "Error in " A_ThisFunc "`nDeviceID = " this.DeviceID ", ErrorLevel: " ErrorLevel ", Device Status: " this.GetStatusName()
			}
			return ret
		}

		; Relinquish the device
		Relinquish(){
			return this.Interface.RelinquishVJD(this.DeviceID)
		}

		; Does the device exist or not?
		IsEnabled(){
			state := this.GetStatus()
			return state != this.Interface.VJD_STAT_MISS && state != this.Interface.VJD_STAT_UNKN
		}

		; Is it possible to take control of the device?
		IsAvailable(){
			state := this.GetStatus()
			return state == this.Interface.VJD_STAT_FREE || state == this.Interface.VJD_STAT_OWN
		}

		; Set Axis by Index number.
		; eg x = 1, y = 2, z = 3, rx = 4
		SetAxisByIndex(index, axis_val){
			if (!this.IsOwned){
				if(!this.Acquire()){
					return 0
				}
			}
			ret := this.Interface.SetAxis(axis_val, this.DeviceID, this.Interface.AxisIndex[index])
			if (!ret && this.Interface.DebugMode) {
				OutputDebug, % "Error in " A_ThisFunc "`nindex = " index ", axis_val = " axis_val
			}
			return ret
		}

		; Set Axis by Name
		; eg "x", "y", "z", "rx"
		SetAxisByName(name, axis_val){
			if (!this.IsOwned){
				if(!this.Acquire()){
					return 0
				}
			}
			ret := this.Interface.SetAxis(axis_val, this.DeviceID, this.Interface.AxisAssoc[name])
			if (!ret && this.Interface.DebugMode) {
				OutputDebug, % "Error in " A_ThisFunc "`nname = " name ", axis_val = " axis_val
			}
			return ret
		}
	}

	; ===== Constructors / Destructors
	__New(){
		; Build Device array
		Loop % this.VJD_MAXDEV {
			this.Devices[A_Index] := new this.CvJoyDevice(A_Index, this)
		}

		; Try and Load the DLL
		this.LoadLibrary()
		return this
	}

	__Delete(){
		; Relinquish Devices
		Loop % this.VJD_MAXDEV {
			this.Devices[A_Index].Relinquish()
		}

		; Unload DLL
		if (this.hModule){
			DllCall("FreeLibrary", "Ptr", this.hModule)
		}
	}

	; ===== DLL loading / vJoy Install detection

	; Load lib from already load or current/system directory
	LoadLibrary() {
		;Global hModule

		if (this.LibraryLoaded) {
			this.LoadLibraryLog .= "Library already loaded. Aborting...`n"
			return 1
		}

		this.LoadLibraryLog := ""

		; Check if vJoy is installed. Even with the DLL, if vJoy is not installed it will not work...
		; Find vJoy install folder by looking for registry key.
		vJoyFolder := this.RegRead64("HKEY_LOCAL_MACHINE", "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8E31F76F-74C3-47F1-9550-E041EEDC5FBB}_is1", "InstallLocation")
		if (!vJoyFolder){
			this.LoadLibraryLog .= "ERROR: Could not find the vJoy Registry Key.`n`nvJoy does not appear to be installed.`nPlease ensure you have installed vJoy from`n`nhttp://vjoystick.sourceforge.net."
			return 0
		}

		; Play hunt-the-DLL
		DllFile := "vJoyInterface.dll"
		this.LoadLibraryLog := "vJoy Install Detected. Trying to locate correct " DllFile "...`n"
		CheckLocations := [vJoyFolder DllFile, vJoyFolder "Feeder\" DllFile, "vjoy_lib\x86\" DllFile, "vjoy_lib\x64\" DllFile]

		hModule := 0
		Loop % CheckLocations.Maxindex() {
			this.LoadLibraryLog .= "Checking " CheckLocations[A_Index] "... "
			if (FileExist(CheckLocations[A_Index])){
				this.LoadLibraryLog .= "FOUND.`nTrying to load.. "
				hModule := DLLCall("LoadLibrary", "Str", CheckLocations[A_Index])
				if (hModule){
					this.hModule := hModule
					this.LoadLibraryLog .= "OK.`n"
					this.LibraryLoaded := 1
					if (this.DebugMode){
						OutputDebug, % this.LoadLibraryLog
					}
					return 1
				} else {
					this.LoadLibraryLog .= "FAILED.`n"
				}
			} else {
				this.LoadLibraryLog .= "NOT FOUND.`n"
			}
		}
		this.LoadLibraryLog .= "`nFailed to load valid  " DllFile "`nThis could be because you have a 64-bit system but the script needs a 32-bit DLL"
		this.LibraryLoaded := 0
		return 0
	}

	; x64 compatible registry read from http://www.autohotkey.com/board/topic/36290-regread64-and-regwrite64-no-redirect-to-wow6432node/
	RegRead64(sRootKey, sKeyName, sValueName = "", DataMaxSize=1024) {
		HKEY_CLASSES_ROOT   := 0x80000000   ; http://msdn.microsoft.com/en-us/library/aa393286.aspx
		HKEY_CURRENT_USER   := 0x80000001
		HKEY_LOCAL_MACHINE  := 0x80000002
		HKEY_USERS          := 0x80000003
		HKEY_CURRENT_CONFIG := 0x80000005
		HKEY_DYN_DATA       := 0x80000006
		HKCR := HKEY_CLASSES_ROOT
		HKCU := HKEY_CURRENT_USER
		HKLM := HKEY_LOCAL_MACHINE
		HKU  := HKEY_USERS
		HKCC := HKEY_CURRENT_CONFIG
		
		REG_NONE                := 0    ; http://msdn.microsoft.com/en-us/library/ms724884.aspx
		REG_SZ                  := 1
		REG_EXPAND_SZ           := 2
		REG_BINARY              := 3
		REG_DWORD               := 4
		REG_DWORD_BIG_ENDIAN    := 5
		REG_LINK                := 6
		REG_MULTI_SZ            := 7
		REG_RESOURCE_LIST       := 8

		KEY_QUERY_VALUE := 0x0001   ; http://msdn.microsoft.com/en-us/library/ms724878.aspx
		KEY_WOW64_64KEY := 0x0100   ; http://msdn.microsoft.com/en-gb/library/aa384129.aspx (do not redirect to Wow6432Node on 64-bit machines)
		KEY_SET_VALUE   := 0x0002
		KEY_WRITE       := 0x20006
		ENC := A_IsUnicode?"W":"A"
		hKey := "", sValueType := ""

		myhKey := %sRootKey%        ; pick out value (0x8000000x) from list of HKEY_xx vars
		IfEqual,myhKey,, {      ; Error - Invalid root key
			ErrorLevel := 3
			return ""
		}
		RegAccessRight := KEY_QUERY_VALUE + KEY_WOW64_64KEY
		;VarSetCapacity(sValueType, 4)
		DllCall("Advapi32.dll\RegOpenKeyEx" ENC, "uint", myhKey, "str", sKeyName, "uint", 0, "uint", RegAccessRight, "uint*", hKey)    ; open key
		DllCall("Advapi32.dll\RegQueryValueEx" ENC, "uint", hKey, "str", sValueName, "uint", 0, "uint*", sValueType, "uint", 0, "uint", 0)     ; get value type
		If (sValueType == REG_SZ or sValueType == REG_EXPAND_SZ) {
			VarSetCapacity(sValue, vValueSize:=DataMaxSize)
			DllCall("Advapi32.dll\RegQueryValueEx" ENC, "uint", hKey, "str", sValueName, "uint", 0, "uint", 0, "str", sValue, "uint*", vValueSize) ; get string or string-exp
		} Else If (sValueType == REG_DWORD) {
			VarSetCapacity(sValue, vValueSize:=4)
			DllCall("Advapi32.dll\RegQueryValueEx" ENC, "uint", hKey, "str", sValueName, "uint", 0, "uint", 0, "uint*", sValue, "uint*", vValueSize)   ; get dword
		} Else If (sValueType == REG_MULTI_SZ) {
			VarSetCapacity(sTmp, vValueSize:=DataMaxSize)
			DllCall("Advapi32.dll\RegQueryValueEx" ENC, "uint", hKey, "str", sValueName, "uint", 0, "uint", 0, "str", sTmp, "uint*", vValueSize)   ; get string-mult
			sValue := this.ExtractData(&sTmp) "`n"
			Loop {
				If (errorLevel+2 >= &sTmp + vValueSize)
					Break
				sValue := sValue this.ExtractData( errorLevel+1 ) "`n" 
			}
		} Else If (sValueType == REG_BINARY) {
			VarSetCapacity(sTmp, vValueSize:=DataMaxSize)
			DllCall("Advapi32.dll\RegQueryValueEx" ENC, "uint", hKey, "str", sValueName, "uint", 0, "uint", 0, "str", sTmp, "uint*", vValueSize)   ; get binary
			sValue := ""
			SetFormat, integer, h
			Loop %vValueSize% {
				hex := SubStr(Asc(SubStr(sTmp,A_Index,1)),3)
				StringUpper, hex, hex
				sValue := sValue hex
			}
			SetFormat, integer, d
		} Else {                ; value does not exist or unsupported value type
			DllCall("Advapi32.dll\RegCloseKey", "uint", hKey)
			ErrorLevel := 1
			return ""
		}
		DllCall("Advapi32.dll\RegCloseKey", "uint", hKey)
		return sValue
	}
	 
	ExtractData(pointer) {  ; http://www.autohotkey.com/forum/viewtopic.php?p=91578#91578 SKAN
		Loop {
				errorLevel := ( pointer+(A_Index-1) )
				Asc := *( errorLevel )
				IfEqual, Asc, 0, Break ; Break if NULL Character
				String := String . Chr(Asc)
			}
		Return String
	}

	; ===== vJoy Interface DLL call wrappers
	; In the order detailed in the vJoy SDK's Interface Function Reference
	; http://sourceforge.net/projects/vjoystick/files/

	; === General driver data
	vJoyEnabled(){
		return DllCall("vJoyInterface\vJoyEnabled")
	}

	GetvJoyVersion(){
		return DllCall("vJoyInterface\GetvJoyVersion")
	}

	GetvJoyProductString(){
		return DllCall("vJoyInterface\GetvJoyProductString")
	}

	GetvJoyManufacturerString(){
		return DllCall("vJoyInterface\GetvJoyManufacturerString")
	}

	GetvJoySerialNumberString(){
		return DllCall("vJoyInterface\GetvJoySerialNumberString")
	}

	; === Write access to vJoy Device
	GetVJDStatus(rID){
		return DllCall("vJoyInterface\GetVJDStatus", "UInt", rID)
	}

	; Handle setting IsOwned property outside helper class, to allow mixing
	AcquireVJD(rID){
		this.Devices[rID].IsOwned := DllCall("vJoyInterface\AcquireVJD", "UInt", rID)
		return this.Devices[rID].IsOwned
	}

	RelinquishVJD(rID){
		this.Devices[rID].IsOwned := DllCall("vJoyInterface\RelinquishVJD", "UInt", rID)
		return this.Devices[rID].IsOwned
	}

	; Not sure if this one is good. What is a "PVOID"?
	UpdateVJD(rID, pData){
		return DllCall("vJoyInterface\UpdateVJD", "UInt", rID, "PVOID", pData)
	}

	; === vJoy Device properties

	GetVJDButtonNumber(rID){
		return DllCall("vJoyInterface\GetVJDButtonNumber", "UInt", rID)
	}

	GetVJDDiscPovNumber(rID){
		return DllCall("vJoyInterface\GetVJDDiscPovNumber", "UInt", rID)
	}

	GetVJDContPovNumber(rID){
		return DllCall("vJoyInterface\GetVJDContPovNumber", "UInt", rID)
	}

	GetVJDAxisExist(rID, Axis){
		return DllCall("vJoyInterface\GetVJDAxisExist", "UInt", rID, "Uint", Axis)
	}

	ResetVJD(rID){
		return DllCall("vJoyInterface\ResetVJD", "UInt", rID)
	}

	ResetAll(){
		return DllCall("vJoyInterface\ResetAll")
	}

	ResetButtons(rID){
		return DllCall("vJoyInterface\ResetButtons", "UInt", rID)
	}

	ResetPovs(rID){
		return DllCall("vJoyInterface\ResetPovs", "UInt", rID)
	}

	SetAxis(Value, rID, Axis){
		return DllCall("vJoyInterface\SetAxis", "Int", Value, "UInt", rID, "UInt", Axis)
	}

	SetBtn(Value, rID, nBtn){
		return DllCall("vJoyInterface\SetBtn", "Int", Value, "UInt", rID, "UInt", nBtn)
	}

	SetDiscPov(Value, rID, nPov){
		return DllCall("vJoyInterface\SetDiscPov", "Int", Value, "UInt", rID, "UChar", nPov)
	}

	SetContPov(Value, rID, nPOV){
		return DllCall("vJoyInterface\SetContPov", "Int", Value, "UInt", rID, "UChar", nPov)
	}

}