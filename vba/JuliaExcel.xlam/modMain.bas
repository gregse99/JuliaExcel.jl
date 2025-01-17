Attribute VB_Name = "modMain"
' Copyright (c) 2021 - Philip Swannell
' License MIT (https://opensource.org/licenses/MIT)
' Document: https://github.com/PGS62/JuliaExcel.jl#readme

Option Explicit
#If VBA7 And Win64 Then
    Declare PtrSafe Function GetCurrentProcessId Lib "kernel32" () As Long
    Public Declare PtrSafe Sub Sleep Lib "kernel32" (ByVal Milliseconds As Long)
    Public Declare PtrSafe Function IsWindow Lib "USER32" (ByVal hWnd As LongPtr) As Long
#Else
    Declare Function GetCurrentProcessId Lib "kernel32" () As Long
    Public Declare Sub Sleep Lib "kernel32" (ByVal Milliseconds As Long)
    Public Declare Function IsWindow Lib "user32" (ByVal hwnd As Long) As Long
#End If

Public Const gPackageName As String = "JuliaExcel"

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaIsRunning
' Purpose   : Returns TRUE if an instance of Julia is running and "listening" to the current Excel
'             session, or FALSE otherwise.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaIsRunning() As Boolean
Attribute JuliaIsRunning.VB_Description = "Returns TRUE if an instance of Julia is running and ""listening"" to the current Excel session, or FALSE otherwise."
Attribute JuliaIsRunning.VB_ProcData.VB_Invoke_Func = " \n14"

          Dim HwndJulia As LongPtr
          Dim WindowPartialTitle As String

1         On Error GoTo ErrHandler
2         WindowPartialTitle = "serving Excel PID " & CStr(GetCurrentProcessId) 'Must be in synch with Julia function JuliaExcel.settitle
3         GetHandleFromPartialCaption HwndJulia, WindowPartialTitle
4         JuliaIsRunning = HwndJulia <> 0

5         Exit Function
ErrHandler:
6         JuliaIsRunning = "#JuliaIsRunning (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaLaunch
' Purpose   : Launches a local Julia session which "listens" to the current Excel session and responds
'             to calls to JuliaEval etc..
' Arguments
' UseLinux  : TRUE to run Julia as a Linux process under Windows Subsystem for Linux; FALSE (the default) to
'             run as a Windows process.
' MinimiseWindow: If TRUE, then the Julia session window is minimised; if FALSE (the default) then the
'             window is sized normally.
' CommandLineOptions: Command line options set when launching Julia.
'             Example : `--threads=auto --banner=no`.
'             https://docs.julialang.org/en/v1/manual/command-line-options/
' Packages  : Packages to load, which must be available in the default Julia environment (or environment set
'             via the `--project` command line option). Delimit multiple packages with commas.
' BashStatements: Relevant only when UseLinux is TRUE. Bash statements executed prior to launching Julia,
'             which can be used to set environment variables. Example `export
'             JULIA_PKG_DEVDIR=/mnt/c/Projects`. Delimit multiple statements with the line feed character.
' TimeOut   : The number of seconds to wait for Julia to launch before the function assumes that launch has
'             failed (perhaps because of mal-formed CommandLineOptions). Optional and defaults to 30.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaLaunch(Optional UseLinux As Boolean, Optional MinimiseWindow As Boolean, _
    Optional ByVal CommandLineOptions As String, Optional ByVal Packages As String, _
    Optional ByVal BashStatements As String, Optional TimeOut As Long = 30)

          Dim Command As String
          Dim CommsFolderX As String
          Dim ErrorFile As String
          Dim ErrorFileX As String
          Dim FlagFileX As String
          Dim HwndJulia As LongPtr
          Dim JuliaExe As String
          Dim LaunchFile As String
          Dim LaunchFileContents As String
          Dim LaunchFileNecessary As Boolean
          Dim LaunchFileX As String
          Dim LoadFile As String
          Dim LoadFileContents As String
          Dim LoadFileX As String
          Dim PID As Long
          Dim WindowPartialTitle As String
          Dim WindowTitle As String
          Dim wsh As WshShell
          Dim usingStatements As String

1         On Error GoTo ErrHandler

2         If IsFunctionWizardActive() Then
3             JuliaLaunch = "#Disabled in Function Wizard!"
4             Exit Function
5         End If

6         JuliaExe = JuliaExeLocation(UseLinux)

7         If InStr(CommandLineOptions, "-L") > 0 Or InStr(CommandLineOptions, "--load ") > 0 Then
8             Throw "CommandLineOptions cannot include the -L or --load options. Instead use JuliaLaunch without that option and then use JuliaCall(""include"",""path_to_file"")"
9         End If

10        PID = GetCurrentProcessId
11        WindowPartialTitle = "serving Excel PID " & CStr(PID) 'Must be in synch with Julia function JuliaExcel.settitle
12        GetHandleFromPartialCaption HwndJulia, WindowPartialTitle

13        If HwndJulia <> 0 Then
14            WindowTitle = WindowTitleFromHandle(HwndJulia)
15            JuliaLaunch = "Julia is already running in window """ & WindowTitle & """"
16            Exit Function
17        End If

18        ErrorFile = LocalTemp() & "\LoadError_" & CStr(GetCurrentProcessId()) & ".txt"
19        If FileExists(ErrorFile) Then Kill ErrorFile
          
20        SaveTextFile JuliaFlagFile, "", TristateFalse
21        LoadFile = LocalTemp() & "\StartUp_" & CStr(GetCurrentProcessId()) & ".jl"

22        If UseLinux Then
23            ErrorFileX = WSLAddress(ErrorFile)
24            FlagFileX = WSLAddress(JuliaFlagFile())
25            CommsFolderX = WSLAddress(LocalTemp())
26            LoadFileX = WSLAddress(LoadFile)
27            If BashStatements <> "" Then
28                LaunchFileNecessary = True
29                BashStatements = BashStatements & vbLf
30                LaunchFile = LocalTemp & "\launchjulia.sh"
31                LaunchFileX = WSLAddress(LaunchFile)
32                LaunchFileContents = _
                      "#!/bin/bash" & vbLf & _
                      BashStatements & _
                      JuliaExe & " " & Trim(CommandLineOptions) & " --load """ & LoadFileX & """"
33                SaveTextFile LaunchFile, LaunchFileContents, TristateFalse
34            End If
35        Else
36            FlagFileX = Replace(JuliaFlagFile(), "\", "/")
37            CommsFolderX = Replace(LocalTemp(), "\", "/")
38            ErrorFileX = Replace(ErrorFile, "\", "/")
39            LoadFileX = Replace(LoadFile, "\", "/")
40        End If

41        If UseLinux Then
42            If LaunchFileNecessary Then
43                Command = "wsl """ & LaunchFileX & """ && exit"
44            Else
45                Command = "wsl " & JuliaExe & " " & Trim(CommandLineOptions) & " --load """ & LoadFileX & """"
46            End If
47        Else
48            Command = """" & JuliaExe & """" & " " & Trim(CommandLineOptions) & " --load """ & LoadFileX & """"
49        End If
          
          Dim LiteralCommand As String
50        LiteralCommand = MakeJuliaLiteral(Command)
51        LiteralCommand = Mid(LiteralCommand, 2, Len(LiteralCommand) - 2)

          Dim PackagesArray() As String, i As Long

          'PGS 8 Dec 2021. It's important to make using JuliaExcel be the last "using" statement as I believe that helps avoid "world-age" problems
52        If Packages = "" Then
53        Packages = "Revise,Dates," & gPackageName
54        Else
55        Packages = "Revise,Dates," & Packages & "," & gPackageName
56        End If
57        PackagesArray = VBA.Split(Packages, ",")

58        For i = LBound(PackagesArray) To UBound(PackagesArray)
59            Select Case PackagesArray(i)
                  Case Else
60                    usingStatements = usingStatements & _
                          "    println(""using " & Trim(PackagesArray(i)) & """)" & vbLf & _
                          "    using " & Trim(PackagesArray(i)) & vbLf
61            End Select
62        Next

63        LoadFileContents = _
              "try" & vbLf & _
              usingStatements & _
              "    setxlpid(" & CStr(GetCurrentProcessId) & ")" & vbLf & _
              "    JuliaExcel.setcommsfolder(""" & CommsFolderX & """)" & vbLf & _
              "    println(""Julia $VERSION, using " & gPackageName & " to serve Excel running as process ID " & GetCurrentProcessId() & "."")" & vbLf & _
              "    println(""Julia launched with command: " & LiteralCommand & " "")" & vbLf & _
              "    rm(""" & FlagFileX & """)" & vbLf & _
              "catch e" & vbLf & _
              "    theerror = ""$e""" & vbLf & _
              "    @error theerror " & vbLf & _
              "    errorfile = """ & ErrorFileX & """" & vbLf & _
              "    io = open(errorfile, ""w"")" & vbLf & _
              "    write(io,theerror)" & vbLf & _
              "    close(io)" & vbLf & _
              "    rm(""" & FlagFileX & """)" & vbLf & _
              "end"

64        SaveTextFile LoadFile, LoadFileContents, TristateFalse
        
65        Set wsh = New WshShell

          Dim NumBefore As Long
          Dim StartTime As Double
66        StartTime = ElapsedTime()
          Dim PartialCaption As String
67        PartialCaption = "serving Excel PID " & CStr(PID)
68        NumBefore = NumWindowsWithCaption(PartialCaption)

69        wsh.Run Command, IIf(MinimiseWindow, vbMinimizedFocus, vbNormalNoFocus), False
          'Unfortunately, if the CommandLineOptions are invalid then Julia does not launch, but the
          'call to wsh.Run does not throw an error. Work-around is to count the number of windows whose
          'caption contains "Julia 1." before and TIMEOUT seconds after the call to wsh.Run.
70        While FileExists(JuliaFlagFile)
71            Sleep 50
72            If ElapsedTime() - StartTime > TimeOut Then
73                If NumWindowsWithCaption(PartialCaption) <> NumBefore + 1 Then
74                    Throw "Julia failed to launch after " + CStr(TimeOut) + " seconds. Check the CommandLineOptions are valid (https://docs.julialang.org/en/v1/manual/command-line-options/)"
75                End If
76            End If
77        Wend
78        CleanLocalTemp
79        If FileExists(ErrorFile) Then
80            Throw "Julia launched but encountered an error when executing '" & LoadFile & "' the error was: " & ReadTextFile(ErrorFile, TristateFalse)
81        End If
          
82        GetHandleFromPartialCaption HwndJulia, WindowPartialTitle
83        WindowTitle = WindowTitleFromHandle(HwndJulia)
          
84        JuliaLaunch = "Julia launched in window """ & WindowTitle & """"

85        Exit Function
ErrHandler:
86        JuliaLaunch = "#JuliaLaunch (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure  : JuliaEval_LowLevel
' Purpose    : Evaluate a Julia expression, exposing more arguments than we should show to the user.
' Parameters :
'  JuliaExpression      :
'  AllowNested          : Should the function throw an error if it detects that the return from Julia cannot be displayed
'                         in a worksheet, for example if it's a dictionary or an array of arrays.
'                         Should be False when calling from a worksheet since Excel would otherwise display a single
'                         "#VALUE!" with no hint as to what caused the problem.
'  StringLengthLimit    : The longest string allowed in (an element of) the return from Julia. If exceeded the function
'                         throws an intelligible error. When calling from the worksheet, should be set to the return from
'                         GetStringLengthLimit, which returns either 255 or 32767 according to the Excel version.
'  JuliaVectorToXLColumn: Should a return from Julia that's a vector (array with one dimension) be unserialised as a two
'                         dimensional array? Should be True when calling from a worksheet, or False when calling from VBA.
'                         In both cases round tripping will work correctly.
' -----------------------------------------------------------------------------------------------------------------------
Private Function JuliaEval_LowLevel(ByVal JuliaExpression As Variant, _
          Optional AllowNested As Boolean, Optional StringLengthLimit As Long, _
          Optional JuliaVectorToXLColumn As Boolean = True)
          
          Dim strJuliaExpression As String
          Dim WindowTitle As String
          Static HwndJulia As LongPtr
          Static JuliaExe As String
          Static PID As Long

1         On Error GoTo ErrHandler

2         strJuliaExpression = ConcatenateExpressions(JuliaExpression)

3         If JuliaExe = "" Then
4             JuliaExe = JuliaExeLocation()
5         End If
6         If PID = 0 Then
7             PID = GetCurrentProcessId()
8         End If
            
9         If HwndJulia = 0 Or IsWindow(HwndJulia) = 0 Then
10            WindowTitle = "serving Excel PID " & CStr(PID)
11            GetHandleFromPartialCaption HwndJulia, WindowTitle
12        End If

13        If HwndJulia = 0 Or IsWindow(HwndJulia) = 0 Then
14            JuliaEval_LowLevel = "#Please call JuliaLaunch before calling JuliaEval or JuliaCall!"
15            Exit Function
16        End If
          
17        SaveTextFile JuliaFlagFile, "", TristateTrue
18        SaveTextFile JuliaExpressionFile, strJuliaExpression, TristateTrue

          'Line below tells Julia to "do the work" by pasting "srv_xl()" to the REPL
19        PostMessageToJulia HwndJulia

20        Do While FileExists(JuliaFlagFile)
21            Sleep 1
22            If IsWindow(HwndJulia) = 0 Then
23                JuliaEval_LowLevel = "#Julia shut down while evaluating the expression!"
24                Exit Function
25            End If
26        Loop
27        Assign JuliaEval_LowLevel, UnserialiseFromFile(JuliaResultFile, AllowNested, StringLengthLimit, JuliaVectorToXLColumn)
28        Exit Function
ErrHandler:
29        Throw "#JuliaEval_LowLevel (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaEval
' Purpose   : Evaluate a Julia expression and return the result to an Excel worksheet.
' Arguments
' JuliaExpression: Any valid Julia code, as a string. Can also be a one-column range to evaluate multiple
'             Julia statements.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaEval(ByVal JuliaExpression As Variant)
Attribute JuliaEval.VB_Description = "Evaluate a Julia expression and return the result to an Excel worksheet."
Attribute JuliaEval.VB_ProcData.VB_Invoke_Func = " \n14"
1         On Error GoTo ErrHandler
          
2         If IsFunctionWizardActive() Then
3             JuliaEval = "#Disabled in Function Wizard!"
4             Exit Function
5         End If

6         Assign JuliaEval, JuliaEval_LowLevel(JuliaExpression, False, GetStringLengthLimit(), True)

7         Exit Function
ErrHandler:
8         JuliaEval = "#JuliaEval (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaEvalVBA
' Purpose   : Evaluate a Julia expression from VBA . Differs from JuliaCall in handling of 1-dimensional
'             arrays, and strings longer than 32,767 characters. May return data of types that cannot be
'             displayed on a worksheet, such as a dictionary or an array of arrays.
' Arguments
' JuliaExpression: Any valid Julia code, as a string. Can also be a one-column range to evaluate multiple
'             Julia statements.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaEvalVBA(ByVal JuliaExpression As Variant)
Attribute JuliaEvalVBA.VB_Description = "Evaluate a Julia expression from VBA . Differs from JuliaCall in handling of 1-dimensional arrays, and strings longer than 32,767 characters. May return data of types that cannot be displayed on a worksheet, such as a dictionary or an array of arrays."
Attribute JuliaEvalVBA.VB_ProcData.VB_Invoke_Func = " \n14"
1         On Error GoTo ErrHandler
2         Assign JuliaEvalVBA, JuliaEval_LowLevel(JuliaExpression, AllowNested:=True, StringLengthLimit:=0, JuliaVectorToXLColumn:=False)
3         Exit Function
ErrHandler:
4         Throw "#JuliaEvalVBA (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaSetVar
' Purpose   : Set a global variable in the Julia process.
' Arguments
' VariableName: The name of the variable to be set. Must follow Julia's rules for allowed variable names.
' RefersTo  : An Excel range (from which the .Value2 property is read) or more generally a number, string,
'             Boolean, Empty or array of such types. When called from VBA, nested arrays are supported.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaSetVar(VariableName As String, RefersTo As Variant)
Attribute JuliaSetVar.VB_Description = "Set a global variable in the Julia process."
Attribute JuliaSetVar.VB_ProcData.VB_Invoke_Func = " \n14"
1         On Error GoTo ErrHandler
2         JuliaSetVar = JuliaCall(gPackageName & ".setvar", VariableName, RefersTo)

3         Exit Function
ErrHandler:
4         JuliaSetVar = "#JuliaSetVar (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaCall
' Purpose   : Call a named Julia function, passing in data from the worksheet.
' Arguments
' JuliaFunction: The name of a Julia function that's defined in the Julia session, perhaps as a result of
'             prior calls to JuliaInclude.
' Args...   : Zero or more arguments. Each argument may be a number, string, Boolean value, empty cell, an
'             array of such values or an Excel range.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaCall(JuliaFunction As String, ParamArray Args())
Attribute JuliaCall.VB_Description = "Call a named Julia function, passing in data from the worksheet."
Attribute JuliaCall.VB_ProcData.VB_Invoke_Func = " \n14"
          Dim Expression As String
          Dim i As Long
          Dim Tmp() As String

1         On Error GoTo ErrHandler

2         If IsFunctionWizardActive() Then
3             JuliaCall = "#Disabled in Function Wizard!"
4             Exit Function
5         End If

6         If UBound(Args) >= LBound(Args) Then
7             ReDim Tmp(LBound(Args) To UBound(Args))

8             For i = LBound(Args) To UBound(Args)
9                 If TypeName(Args(i)) = "Range" Then Args(i) = Args(i).Value2
10                Tmp(i) = MakeJuliaLiteral(Args(i))
11            Next i
12            Expression = JuliaFunction & "(" & VBA.Join$(Tmp, ",") & ")"
13        Else
14            Expression = JuliaFunction & "()"
15        End If

16        JuliaCall = JuliaEval(Expression)

17        Exit Function
ErrHandler:
18        JuliaCall = "#JuliaCall (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaCallVBA
' Purpose   : Call a named Julia function from VBA. Differs from JuliaCall in handling of 1-dimensional
'             arrays, and strings longer than 32,767 characters. May return data of types that cannot be
'             displayed on a worksheet, such as a dictionary or an array of arrays.
' Arguments
' JuliaFunction: The name of a Julia function that's defined in the Julia session, perhaps as a result of
'             prior calls to JuliaInclude.
' Args...   : Zero or more arguments. Each argument may be a number, string, Boolean value, empty cell, an
'             array of such values or an Excel range.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaCallVBA(JuliaFunction As String, ParamArray Args())
Attribute JuliaCallVBA.VB_Description = "Call a named Julia function from VBA. Differs from JuliaCall in handling of 1-dimensional arrays, and strings longer than 32,767 characters. May return data of types that cannot be displayed on a worksheet, such as a dictionary or an array of arrays."
Attribute JuliaCallVBA.VB_ProcData.VB_Invoke_Func = " \n14"
          Dim Expression As String
          Dim i As Long
          Dim Tmp() As String

1         On Error GoTo ErrHandler
2         If UBound(Args) >= LBound(Args) Then
3             ReDim Tmp(LBound(Args) To UBound(Args))
4             For i = LBound(Args) To UBound(Args)
5                 If TypeName(Args(i)) = "Range" Then Args(i) = Args(i).Value2
6                 Tmp(i) = MakeJuliaLiteral(Args(i))
7             Next i
8             Expression = JuliaFunction & "(" & VBA.Join$(Tmp, ",") & ")"
9         Else
10            Expression = JuliaFunction & "()"
11        End If

12        Assign JuliaCallVBA, JuliaEval_LowLevel(Expression, AllowNested:=True, StringLengthLimit:=0, JuliaVectorToXLColumn:=False)

13        Exit Function
ErrHandler:
14        Throw "#JuliaCallVBA (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaInclude
' Purpose   : Load a Julia source file into the Julia process, to make additional functions available
'             via JuliaEval and JuliaCall.
' Arguments
' FileName  : The full name of the file to be included.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaInclude(FileName As String)
Attribute JuliaInclude.VB_Description = "Load a Julia source file into the Julia process, to make additional functions available via JuliaEval and JuliaCall."
Attribute JuliaInclude.VB_ProcData.VB_Invoke_Func = " \n14"
1         If IsFunctionWizardActive() Then
2             JuliaInclude = "#Disabled in Function Wizard!"
3             Exit Function
4         End If
5         JuliaInclude = JuliaCall(gPackageName & ".include", Replace(FileName, "\", "/"))
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaUnserialiseFile
' Purpose   : Unserialises the contents of the JuliaResultsFile.
' Arguments
' FileName  : The name (including path) of the file to be unserialised. Optional and defaults to the file
'             name returned by JuliaResultsFile.
' ForWorksheet: Pass TRUE (the default) when calling from a worksheet, FALSE when calling from VBA. If
'             FALSE, the function may return data structures that can exist in VBA but cannot be
'             represented on a worksheet, such as a dictionary or an array of arrays.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaUnserialiseFile(Optional ByVal FileName As String, Optional ForWorksheet As Boolean = True)
Attribute JuliaUnserialiseFile.VB_Description = "Unserialises the contents of the JuliaResultsFile."
Attribute JuliaUnserialiseFile.VB_ProcData.VB_Invoke_Func = " \n14"
          Dim StringLengthLimit As Long
          Dim JuliaVectorToXLColumn As Boolean

1         On Error GoTo ErrHandler
2         If FileName = "" Then
3             FileName = JuliaResultFile()
4         End If

5         If ForWorksheet Then
6             StringLengthLimit = GetStringLengthLimit()
7             JuliaVectorToXLColumn = True
8         End If

9         Assign JuliaUnserialiseFile, UnserialiseFromFile(FileName, Not ForWorksheet, StringLengthLimit, JuliaVectorToXLColumn)

10        Exit Function
ErrHandler:
11        JuliaUnserialiseFile = "#JuliaUnserialiseFile (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaFlagFile
' Purpose   : Returns the name of a sentinel file. The file is created (by VBA code) at the same time as
'             the expression file and deleted (by Julia code) when Julia execution has finished.
' -----------------------------------------------------------------------------------------------------------------------
Private Function JuliaFlagFile() As String
          Static FlagFile As String
1         If FlagFile = "" Then
2             FlagFile = LocalTemp() & "\Flag_" & CStr(GetCurrentProcessId()) & ".txt"
3         End If
4         JuliaFlagFile = FlagFile
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaExpressionFile
' Purpose   : Returns the name of the file containing the JuliaExpression that's passed to JuliaEval,
'             JuliaCall etc.
' -----------------------------------------------------------------------------------------------------------------------
Private Function JuliaExpressionFile() As String
          Static ExpressionFile As String
1         If ExpressionFile = "" Then
2             ExpressionFile = LocalTemp() & "\Expression_" & CStr(GetCurrentProcessId()) & ".txt"
3         End If
4         JuliaExpressionFile = ExpressionFile
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : JuliaResultFile
' Purpose   : Returns the name of the file to which the results of calls to JuliaCall, JuliaEval etc.
'             are written. The file may be unserialised with function JuliaUnserialiseFile.
' -----------------------------------------------------------------------------------------------------------------------
Public Function JuliaResultFile() As String
Attribute JuliaResultFile.VB_Description = "Returns the name of the file to which the results of calls to JuliaCall, JuliaEval etc. are written. The file may be unserialised with function JuliaUnserialiseFile."
Attribute JuliaResultFile.VB_ProcData.VB_Invoke_Func = " \n14"
          Static ResultFile As String
1         If ResultFile = "" Then
2             ResultFile = LocalTemp() & "\Result_" & CStr(GetCurrentProcessId()) & ".txt"
3         End If
4         JuliaResultFile = ResultFile
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure  : JuliaExeLocation
' Purpose    : Returns the location of the Julia executable. First looks at the path, and if not found looks at the
'              locations to which Julia is (by default) installed. If more than one version is found then returns the
'              most recently installed.
' -----------------------------------------------------------------------------------------------------------------------
Private Function JuliaExeLocation(Optional UseLinux As Boolean)

          Dim ChildFolder As Scripting.Folder
          Dim ChosenExe As String
          Dim CreatedDate As Double
          Dim ErrString As String
          Dim ExeFile As String
          Dim Folder As String
          Dim FSO As New FileSystemObject
          Dim i As Long
          Dim ParentFolder As Scripting.Folder
          Dim ParentFolderName As String
          Dim Path As String
          Dim Paths() As String
          Dim ThisCreatedDate As Double
          Dim JuliaLinuxExeWindowsAddress As String

1         On Error GoTo ErrHandler
          
2         If UseLinux Then
              'This is fragile. Assumes Ubuntu, not some other Linux distribution.

              Const JuliaExeOnWSL = "/usr/local/bin/julia"
              Const WSLRoot = "\\wsl$\Ubuntu" 'should work both on Wiondows 10 and Windows 11 (which uses \\wsl.localhost, but seems to support \\wsl$)

3             JuliaLinuxExeWindowsAddress = WSLRoot + Replace(JuliaExeOnWSL, "/", "\")
          
4             If Not FileExists(JuliaLinuxExeWindowsAddress) Then
5                 Throw "Cannot find the Julia executable on Windows Subsystem for Linux. Expected to find a file (or more likely a symbolic link) at '" & JuliaLinuxExeWindowsAddress & "'"
6             End If
7             JuliaExeLocation = JuliaExeOnWSL
8             Exit Function
9         End If
          
          'First search on PATH
10        Path = Environ("PATH")
11        Paths = VBA.Split(Path, ";")
12        For i = LBound(Paths) To UBound(Paths)
13            Folder = Paths(i)
14            If Right(Folder, 1) <> "\" Then Folder = Folder + "\"
15            ExeFile = Folder + "julia.exe"
16            If FileExists(ExeFile) Then
17                JuliaExeLocation = ExeFile
18                Exit Function
19            End If
20        Next i

          'If not found on path, search in the locations to which the windows installer installs
          'julia (if the user accepts defaults) and choose the most recently installed

21        ParentFolderName = Environ("LOCALAPPDATA") & "\Programs"
22        Set ParentFolder = FSO.GetFolder(ParentFolderName)

23        For Each ChildFolder In ParentFolder.SubFolders
24            If Left(ChildFolder.Name, 5) = "Julia" Then
25                ExeFile = ParentFolder & "\" & ChildFolder.Name & "\bin\julia.exe"
26                If FileExists(ExeFile) Then
27                    ThisCreatedDate = ChildFolder.DateCreated
28                    If ThisCreatedDate > CreatedDate Then
29                        CreatedDate = ThisCreatedDate
30                        ChosenExe = ExeFile
31                    End If
32                End If
33            End If
34        Next
          
35        If ChosenExe = "" Then
36            ErrString = "Julia executable not found, after looking on the path and then in sub-folders of " + _
                  ParentFolderName + " which is the default location for Julia on Windows"
37            Throw ErrString
38        Else
39            JuliaExeLocation = ChosenExe
40        End If

41        Exit Function
ErrHandler:
42        Throw "#JuliaExeLocation (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure  : Assign
' Purpose    : Assign b to a whether or not b is an object.
' -----------------------------------------------------------------------------------------------------------------------
Sub Assign(ByRef a, b)
1         If IsObject(b) Then
2             Set a = b
3         Else
4             Let a = b
5         End If
End Sub

' -----------------------------------------------------------------------------------------------------------------------
' Procedure : ThrowIfError
' Purpose   : In the event of an error, methods intended to be callable from spreadsheets
'             return an error string (starts with "#", ends with "!"). ThrowIfError allows such
'             methods to be used from VBA code while keeping error handling robust
'             MyVariable = ThrowIfError(MyFunctionThatReturnsAStringIfAnErrorHappens(...))
' -----------------------------------------------------------------------------------------------------------------------
Function ThrowIfError(Data As Variant)
1         ThrowIfError = Data
2         If VarType(Data) = vbString Then
3             If Left$(Data, 1) = "#" Then
4                 If Right$(Data, 1) = "!" Then
5                     Throw CStr(Data)
6                 End If
7             End If
8         End If
End Function

' -----------------------------------------------------------------------------------------------------------------------
' Procedure  : ConcatenateExpressions
' Purpose    : It's convenient to be able to pass in a multi-line expression, which we first concatenate with semi-colon
'              delimiter before passing to Julia for evaluation
' -----------------------------------------------------------------------------------------------------------------------
Private Function ConcatenateExpressions(JuliaExpression As Variant) As String
          Dim i As Long
          Dim NC As Long
          Dim Tmp() As String
1         On Error GoTo ErrHandler
2         If TypeName(JuliaExpression) = "Range" Then
3             JuliaExpression = JuliaExpression.Value
4         End If
5         Select Case NumDimensions(JuliaExpression)
              Case 0
6                 ConcatenateExpressions = CStr(JuliaExpression)
7             Case 1
8                 ConcatenateExpressions = VBA.Join(JuliaExpression, ";")
9             Case 2
10                NC = UBound(JuliaExpression, 2) - LBound(JuliaExpression, 1) + 1
11                If NC > 1 Then Throw "When passed as an array or a Range, JuliaExpression should have only one column, but got " + CStr(NC) + " columns"
12                ReDim Tmp(LBound(JuliaExpression, 1) To UBound(JuliaExpression, 1))
13                For i = LBound(Tmp) To UBound(Tmp)
14                    Tmp(i) = JuliaExpression(i, LBound(JuliaExpression, 2))
15                Next
16                ConcatenateExpressions = VBA.Join(Tmp, ";")
17            Case Else
18                Throw "Too many dimensions in JuliaExpression"
19        End Select
20        Exit Function
ErrHandler:
21        Throw "#ConcatenateExpressions (line " & CStr(Erl) + "): " & Err.Description & "!"
End Function

'--------------------------------------------------
'05-Nov-2021 16:18:37        DESKTOP-0VD2AF0
'Expression = fill("xxx", 1000, 1000)
'Average time in JuliaEval    1.47189380999916
'--------------------------------------------------
'06-Nov-2021 12:28:58        PHILIP-LAPTOP
'Expression = fill("xxx", 1000, 1000)
'Average time in JuliaEval    1.9295860900078
'--------------------------------------------------
'30-Nov-2021 10:13:30        PHILIP-LAPTOP
'Expression = fill("xxx", 1000, 1000)
'Average time in JuliaEval    2.82354638000252  <--- Mmm, why the slowdown since 6-Nov version? Use of Assign?
'--------------------------------------------------
'01-Dec-2021 10:30:10       DESKTOP-0VD2AF0
'Expression = fill("xxx",1000,1000)
'Average time in JuliaEval   2.25666286000051   <-- also seeing slowdown on PC in the office
'--------------------------------------------------
Private Sub SpeedTest()

          Const Expression As String = "fill(""xxx"",1000,1000)"
          Const UseLinux As Boolean = True
          Const NumCalls = 10
          Dim i As Long
          Dim Res
          Dim t1 As Double
          Dim t2 As Double

1         JuliaLaunch , , , UseLinux
2         t1 = ElapsedTime
3         For i = 1 To NumCalls
4             Res = JuliaEval(Expression)
5         Next i
6         t2 = ElapsedTime

7         Debug.Print "'" & Format(Now(), "dd-mmm-yyyy hh:mm:ss"), Environ("ComputerName")
8         Debug.Print "'Expression = " & Expression
9         Debug.Print "'Average time in JuliaEval", (t2 - t1) / NumCalls
10        Debug.Print "'--------------------------------------------------"
End Sub

