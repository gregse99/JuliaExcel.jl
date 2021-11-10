' Installer for JuliaExcel.xlam
' Philip Swannell 4 Nov 2021

'To Debug this file, install visual studio set up for debugging 
'Then run from a command prompt (in the appropriate folder)
'cscript.exe /x Install.vbs
'https://www.codeproject.com/Tips/864659/How-to-Debug-Visual-Basic-Script-with-Visual-Studi

Option Explicit

Const AddinName = "JuliaExcel.xlam"
Const website = "https://github.com/PGS62/JuliaExcel.jl"

Dim gErrorsEncountered
Dim myWS, AddinsDest, MsgBoxTitle, MsgBoxTitleBad
Dim GIFRecordingMode

Function IsProcessRunning(strComputer, strProcess)
    Dim Process, strObject
    IsProcessRunning = False
    strObject = "winmgmts://" & strComputer
    For Each Process In GetObject(strObject).InstancesOf("win32_process")
        If UCase(Process.Name) = UCase(strProcess) Then
            IsProcessRunning = True
            Exit Function
        End If
    Next
End Function

Function CheckProcess(TheProcessName)
    Dim exc, result
    exc = IsProcessRunning(".", TheProcessName)
    If (exc = True) Then
        result = MsgBox(TheProcessName & _
        " is running. Please close it and then click OK to continue.", _
        vbOKOnly + vbExclamation, MsgBoxTitle)
        exc = IsProcessRunning(".", TheProcessName)
        If (exc = True) Then
            result = MsgBox(TheProcessName & " is still running. Please close the " & _
                    "program and restart the installation." + vbLf + vbLf + _
                    "Can't see " & TheProcessName & "?" & vbLf & "Use Windows Task " & _
                    "Manager to check for a ""ghost"" process.", _
                    vbOKOnly + vbExclamation, MsgBoxTitle)
            WScript.Quit
        End If
    End If
End Function

Function FolderExists(TheFolderName)
    Dim fso
    Set fso = CreateObject("Scripting.FileSystemObject")
    FolderExists = fso.FolderExists(TheFolderName)
End Function

Function FolderIsWritable(FolderPath)
          Dim FName
          Dim fso
          Dim Counter
          Dim EN
          Dim T

         If (Right(FolderPath, 1) <> "\") Then FolderPath = FolderPath & "\"
         Set fso = CreateObject("Scripting.FileSystemObject")
         If Not fso.FolderExists(FolderPath) Then
             FolderIsWritable = False
         Else
             Do
                 FName = FolderPath & "TempFile" & Counter & ".tmp"
                 Counter = Counter + 1
            Loop Until Not FileExists(FName)
            On Error Resume Next
            Set T = fso.OpenTextFile(FName, 2, True)
            EN = Err.Number
            On Error GoTo 0
            If EN = 0 Then
                T.Close
                fso.GetFile(FName).Delete
                FolderIsWritable = True
            Else
                FolderIsWritable = False
            End If
        End If

End Function

Function DeleteFolder(TheFolderName)
    Dim fso, f
    Set fso = CreateObject("Scripting.FileSystemObject")
    On Error Resume Next
    f = fso.DeleteFolder(TheFolderName)
    If Err.Number <> 0 Then
        gErrorsEncountered = True
        MsgBox "Failed to delete folder '" & TheFolderName & "'" & vbLf & _
            Err.Description, vbExclamation, MsgBoxTitleBad
    End If
End Function

Function DeleteFile(FileName)
    Dim fso
    Set fso = CreateObject("Scripting.FileSystemObject")
    On Error Resume Next
    fso.GetFile(FileName).Delete
    If Err.Number <> 0 Then
        gErrorsEncountered = True
        MsgBox "Failed to delete file '" & FileName & "'" & vbLf & _
            Err.Description, vbExclamation, MsgBoxTitleBad
    End If
End Function

Function FileExists(FileName)
    Dim fso, f
    Set fso = CreateObject("Scripting.FileSystemObject")
    On Error Resume Next
    Set f = fso.GetFile(FileName)
    On Error GoTo 0
    FileExists = TypeName(f) <> "Empty"
    Exit Function
End Function

'Pass FileNames as a string, comma-delimited for multiple files
Function CopyNamedFiles(ByVal TheSourceFolder, ByVal TheDestinationFolder, _
                        ByVal FileNames, ThrowErrorIfNoSourceFile)
    Dim fso
    Dim FileNamesArray, i, ErrorMessage
    Set fso = CreateObject("Scripting.FileSystemObject")
    If (Right(TheSourceFolder, 1) <> "\") Then
        TheSourceFolder = TheSourceFolder & "\"
    End If
    If (Right(TheDestinationFolder, 1) <> "\") Then
        TheDestinationFolder = TheDestinationFolder & "\"
    End If

    FileNamesArray = Split(FileNames, ",")
    For i = LBound(FileNamesArray) To UBound(FileNamesArray)
        If Not (FileExists(TheSourceFolder & FileNamesArray(i))) Then
            If ThrowErrorIfNoSourceFile Then
                gErrorsEncountered = True
                ErrorMessage = "Cannot find file: " & TheSourceFolder & FileNamesArray(i)
                MsgBox ErrorMessage, vbOKOnly + vbExclamation, MsgBoxTitleBad
            End If
        Else
            if FileExists(TheDestinationFolder & FileNamesArray(i)) Then
                On Error Resume Next
                MakeFileWritable TheDestinationFolder & FileNamesArray(i)
            End If
            On Error Resume Next
            fso.CopyFile TheSourceFolder & FileNamesArray(i), _
                         TheDestinationFolder & FileNamesArray(i), True
            If Err.Number <> 0 Then
                gErrorsEncountered = True
                ErrorMessage = "Failed to copy from: " & _
                    TheSourceFolder & FileNamesArray(i) & vbLf & _
                    "to: " & TheDestinationFolder & FileNamesArray(i) & vbLf & _
                    "Error: " & Err.Description
                MsgBox ErrorMessage, vbOKOnly + vbExclamation, MsgBoxTitleBad
            End If
        End If
    Next
End Function

Function MakeFileWritable(FileName)
    Const ReadOnly = 1
    Dim fso
    Dim f
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set f = fso.GetFile(FileName)
    If f.Attributes And ReadOnly Then
       f.Attributes = f.Attributes XOR ReadOnly 
    End If
End Function

Function ForceFolderToExist(TheFolderName)
    If FolderExists(TheFolderName) = False Then
        Dim fso
        Set fso = CreateObject("Scripting.FileSystemObject")
        fso.CreateFolder (TheFolderName)
    End If
End Function

'---------------------------------------------------------------------------------------
' Procedure : GetAltStartupPath
' Author    : Philip Swannell
' Date      : Nov-2017
' Purpose   : Gets the AltStartupPath, by looking in the Registry
'             There is some chance that this returns the wrong result - e.g. on a PC
'             where Office 16.0 was previously installed (leaving data in the Registry)
'             but the version of Office used is Office 15.0 - For example the "Bloomberg PC"
'             in Solum's offices
'---------------------------------------------------------------------------------------
Function GetAltStartupPath() 'App)
    GetAltStartupPath = RegistryRead("HKEY_CURRENT_USER\Software\Microsoft\Office\" & _
    OfficeVersion(1) & "\Excel\Options\AltStartup", "Not found")
End Function

'---------------------------------------------------------------------------------------
' Procedure : SetAltStartupPath
' Author    : Philip Swannell
' Date      : Nov-2017
' Purpose   : Sets the AltStartupPath, by looking in the Registry. See caution for 
'             GetAltStartupPath
'---------------------------------------------------------------------------------------
Function SetAltStartupPath(Path) '(App,Path)
    RegistryWrite "HKEY_CURRENT_USER\Software\Microsoft\Office\" & OfficeVersion(1) & _
    "\Excel\Options\AltStartup", Path
End Function

'---------------------------------------------------------------------------------------
' Procedure : RegistryRead
' Author    : Philip Swannell
' Date      : 30-Nov-2017
' Purpose   : Read a value from the Registry
' https://msdn.microsoft.com/en-us/library/x05fawxd(v=vs.84).aspx
'---------------------------------------------------------------------------------------
Function RegistryRead(RegKey, DefaultValue)
    RegistryRead = DefaultValue
    Set myWS = CreateObject("WScript.Shell")
    On Error Resume Next
    RegistryRead = myWS.RegRead(RegKey) 
    Exit Function
End Function

'---------------------------------------------------------------------------------------
' Procedure : RegistryWrite
' Author    : Philip Swannell
' Date      : 30-Nov-2017
' Purpose   : Write to the Registry
' https://msdn.microsoft.com/en-us/library/yfdfhz1b(v=vs.84).aspx
'---------------------------------------------------------------------------------------
Function RegistryWrite(RegKey, NewValue)
    Dim myWS
    Set myWS = CreateObject("WScript.Shell")
    myWS.RegWrite RegKey, NewValue, "REG_SZ"
End Function

'---------------------------------------------------------------------------------------
' Procedure : sRegistryKeyExists
' Author    : Philip Swannell
' Date      : 25-Apr-2016
' Purpose   : Returns True or False according to whether a RegKey exists in the Registry
'---------------------------------------------------------------------------------------
Function RegistryKeyExists(RegKey)
    Dim myWS, Res
    Res = Empty
    Set myWS = CreateObject("WScript.Shell")
    On Error Resume Next
    Res = myWS.RegRead(RegKey)
    On Error GoTo 0
    RegistryKeyExists = Not (IsEmpty(Res))
End Function

Function RegistryDelete(RegKey)
    Set myWS = CreateObject("WScript.Shell")
    myWS.regDelete RegKey
End Function

Function OfficeVersion(NumDecimalsAfterPoint)
    Dim i, RegKey
    For i = 20 To 11 Step -1
        RegKey = "HKEY_CURRENT_USER\Software\Microsoft\Office\" & FormatNumber(i, 1) & _
        "\Excel\"
        If RegistryKeyExists(RegKey) Then
            OfficeVersion = FormatNumber(i, NumDecimalsAfterPoint)
            Exit Function
        End If
    Next
    OfficeVersion = "Office Not found"
End Function

Function IIf( expr, truepart, falsepart )
   IIf = falsepart
   If expr Then IIf = truepart
End Function

Function Environ(Expression)
	Dim WshShell
	Set WshShell = CreateObject("WScript.Shell")
	Environ = WshShell.ExpandEnvironmentStrings("%" & Expression & "%")
End Function

Sub InstallExcelAddin(AddinFullName, WithSlashR)
    Dim RegKeyBranch
    Dim RegKeyLeaf
    Dim i
    Dim Found
    Dim NumAddins
    Dim RegValue

    RegKeyBranch = "HKEY_CURRENT_USER\Software\Microsoft\Office\" & _
                    OfficeVersion(1) & "\Excel\Options\"
    i = 0
    Do
        i = i + 1
        RegKeyLeaf = "OPEN" & IIf(i > 1, CStr(i - 1), "")
        If RegistryKeyExists(RegKeyBranch & RegKeyLeaf) Then
            NumAddins = NumAddins + 1
            RegValue = RegistryRead(RegKeyBranch & RegKeyLeaf, "")
            Found = InStr(LCase(RegValue), LCase(AddinFullName)) > 0
            If Found Then Exit Sub
        Else
            Exit Do
        End If
    Loop

    RegKeyLeaf = "OPEN" & IIf(NumAddins > 0, CStr(NumAddins), "")
    'I can't discover what is the significance of the /R that appears in the Registry for
    'some addins but not for others...
    If WithSlashR Then
        RegValue = "/R """ & AddinFullName & """"
    Else
        RegValue = AddinFullName
    End If
    RegistryWrite RegKeyBranch + RegKeyLeaf, RegValue

End Sub

'*******************************************************************************************
'Effective start of this VBScript. Note elevating to admin as per 
'http://www.winhelponline.com/blog/vbscripts-and-uac-elevation/
'We install to C:\ProgramData see
'https://stackoverflow.com/questions/22107812/privileges-owner-issue-when-writing-in-c-programdata
'*******************************************************************************************
If WScript.Arguments.length = 0 Then
   Dim objShell, ThisFileName
   Set objShell = CreateObject("Shell.Application")
   'Pass a bogus argument, say [ uac]
   ThisFileName = WScript.ScriptFullName
   objShell.ShellExecute "wscript.exe", Chr(34) & _
      ThisFileName & Chr(34) & " uac", "", "runas", 1
Else
    Set myWS = CreateObject("WScript.Shell")
    
    MsgBoxTitle = "Install JuliaExcel"
    MsgBoxTitleBad = "Install JuliaExcel - Error Encountered"
    'Hack to make it easy to record a GIF of the installation process without an 
    'installation actually happening
   ' GIFRecordingMode = FileExists("C:\Temp\RecordingGIF.tmp")
    GIFRecordingMode = False

    gErrorsEncountered = False
    if Not GIFRecordingMode Then
        CheckProcess "Excel.exe"
    End If

    if OfficeVersion(0) = "Office Not found" Then
        MsgBox "Installation cannot proceed because no version of Microsoft Office has " & _
               "been detected on this PC." & vblf  & vblf & _
               "The script attempts to detect installed versions of Office by looking " & _
               "in the Windows Registry for a key " & _ 
               "'HKEY_CURRENT_USER\Software\Microsoft\Office\<OFFICE_VERSION_NUMBER>\Excel\Options\'," & _
               " but no such key was found.",vbCritical,MsgBoxTitleBad
        WScript.Quit
    End If

    ' Putting the add-in in the same folder for all users has both advantages and 
    ' disadvantages:
    ' Advantage: Avoid "Excel Link Hell" caused by the fact that workbooks store the 
    '     absolute address of files to which they link (unless the file is in the same 
    '     folder). Causes endless problems when two users share a workbook.
    ' Disadvantage: Two different users of the same PC would share copy of the add-in and 
    '     thus be forced to use the same version of the add-in, though they don't both have 
    '     to have the addin installed since that's controlled via the registry, which _is_ 
    '     user specific.
    AddinsDest = "C:\ProgramData\JuliaExcel\"
    
    Dim AddinsSource
    AddinsSource = WScript.ScriptFullName
    AddinsSource = Left(AddinsSource, InStrRev(AddinsSource, "\") - 1)
    AddinsSource = Left(AddinsSource, InStrRev(AddinsSource, "\"))
    AddinsSource = AddinsSource & "workbooks\"

    Dim Prompt
    Prompt = "This will copy JuliaExcel.xlsm from " & vbLf & vblf & _
        AddinsSource & vbLf & vbLf & _
        "to:" & vblf & vblf & _
        AddinsDest & vblf & vblf & _
        "and install it as an Excel add-in," & vblf & _
        "via Excel > File > Options > Add-ins > Excel Add-ins." & vblf & vblf & _
        "Do you wish to continue?"
    Dim result

    result = MsgBox(Prompt, vbYesNo + vbQuestion, MsgBoxTitle)
    if result <> vbYes Then WScript.Quit

    ForceFolderToExist AddinsDest

    If not GIFRecordingMode Then
        'Copy it.
        CopyNamedFiles AddinsSource, AddinsDest, AddinName, True
        'Make Excel "see" it.
        InstallExcelAddin AddinsDest & AddinName, True
    End If

    If gErrorsEncountered Then
        Prompt = "The install script has finished, but errors were encountered, " & _
                 "which may mean the software will not work correctly." & vblf & vblf & _
                 website
        MsgBox Prompt, vbOKOnly + vbCritical, MsgBoxTitleBad
    Else
        Prompt = "JuliaExcel is installed, and its functions such as JuliaEval and " & _
                 "JuliaCall will be available the next time you start Excel." & vblf & _
                 vblf & website
        MsgBox Prompt, vbOKOnly + vbInformation, MsgBoxTitle
    End If

    WScript.Quit
End If
