﻿VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsDbModule"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'---------------------------------------------------------------------------------------
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This class extends the IDbComponent class to perform the specific
'           : operations required by this particular object type.
'           : (I.e. The specific way you export or import this component.)
'---------------------------------------------------------------------------------------
Option Compare Database
Option Explicit

Private Const ModuleName As String = "clsDbModule"

Private m_Module As AccessObject
Private m_AllItems As Collection
Private m_blnModifiedOnly As Boolean

Private Type udtVbaFileContent
    strContent As String
    blnIsClass As Boolean
End Type

' This requires us to use all the public methods and properties of the implemented class
' which keeps all the component classes consistent in how they are used in the export
' and import process. The implemented functions should be kept private as they are called
' from the implementing class, not this class.
Implements IDbComponent


'---------------------------------------------------------------------------------------
' Procedure : Export
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Export the individual database component (table, form, query, etc...)
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Export()
    
    Dim strTempFile As String
    Dim strExt As String
    Dim strAlternateFile As String

    ' Export to temp file and convert to UTF-8 encoding
    strTempFile = GetTempFile
    ExportVbComponent strTempFile
    ConvertAnsiUtf8 strTempFile, IDbComponent_SourceFile
    
    ' Remove any file with the same name but alternate extension
    strExt = IIf(GetExtension = ".bas", ".cls", ".bas")
    strAlternateFile = IDbComponent_BaseFolder & GetSafeFileName(m_Module.Name) & strExt
    If FSO.FileExists(strAlternateFile) Then DeleteFile strAlternateFile
    
    ' Update the index with the current VBA hash. (Note, this will not show
    ' changes to the hidden VBE properties that might have been added.)
    VCSIndex.Update Me, eatExport, GetCodeModuleHash(edbModule, m_Module.Name)
        
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Import
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Import the individual database component from a file.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Import(strFile As String)

    Dim strName As String
    Dim strTempFile As String
    Dim udtFile As udtVbaFileContent
    
    ' Only import files with the correct extension.
    If Not (strFile Like "*.bas" Or strFile Like "*.cls") Then Exit Sub
    
    ' Parse source file
    strName = GetObjectNameFromFileName(strFile)
    udtFile = ParseSourceFile(strFile, strName)
    
    ' Write to a new file using system encoding (converting from UTF-8)
    strTempFile = GetTempFile
    WriteFile udtFile.strContent, strTempFile, GetSystemEncoding
    
    ' Import the source code
    LoadVbeModuleFromFile strTempFile, strName
    
    ' Make sure the correct project is active before saving.
    Set VBE.ActiveVBProject = GetVBProjectForCurrentDB
    DoCmd.Save acModule, strName
    
    ' Set reference to object
    Set m_Module = CurrentProject.AllModules(strName)
        
    ' Save hash, update the index, and remove the temp file
    VCSIndex.Update Me, eatImport, GetCodeModuleHash(IDbComponent_ComponentType, strName)
    DeleteFile strTempFile
    
End Sub


'---------------------------------------------------------------------------------------
' Procedure : ParseSourceFile
' Author    : Adam Waller
' Date      : 7/13/2021
' Purpose   : Parse the source file to build VBE content
'---------------------------------------------------------------------------------------
'
Private Function ParseSourceFile(strFile As String, strName As String) As udtVbaFileContent

    Dim strLines() As String
    Dim strTLine As String
    Dim lngLine As Long
    Dim cData As clsConcat
    Dim blnIsClass As Boolean
    Dim blnHasHeader As Boolean
        
    Perf.OperationStart "Parse VBA Module"
    
    ' Read file contents into array of lines
    strLines = Split(ReadFile(strFile), vbCrLf)
    
    ' Loop through first several lines to determine type and header
    For lngLine = 0 To UBound(strLines)
        If strLines(lngLine) = "VERSION 1.0 CLASS" Then
            ' Class with VBE header
            blnIsClass = True
            blnHasHeader = True
            Exit For
        ElseIf StartsWith(strLines(lngLine), "Attribute VB_Name = """) Then
            ' Module with VBE header
            blnHasHeader = True
            Exit For
        ElseIf StartsWith(strLines(lngLine), "Attribute VB_GlobalNameSpace = ") Then
            ' Class with no header
            blnIsClass = True
            Exit For
        End If
        ' Exit after 10 lines
        If lngLine > 8 Then Exit For
    Next lngLine
    
    ' Use concatenation class to build file contents
    Set cData = New clsConcat
    With cData
        .AppendOnAdd = vbCrLf
        
        ' Build header, if needed
        If Not blnHasHeader Then
            If blnIsClass Then
                .Add "VERSION 1.0 CLASS"
                .Add "BEGIN"
                .Add "  MultiUse = -1  'True"
                .Add "END"
            End If
            .Add "Attribute VB_Name = """, strName, """"
        End If
    
        ' Add in file contents
        For lngLine = 0 To UBound(strLines)
            .Add strLines(lngLine)
        Next lngLine
        
        ' Remove trailing vbCrLf
        .Remove 2
    End With
    
    ' Return values
    With ParseSourceFile
        .blnIsClass = blnIsClass
        .strContent = cData.GetStr
    End With
    
    Perf.OperationEnd
    
End Function


'---------------------------------------------------------------------------------------
' Procedure : LoadVbeModuleFromFile
' Author    : Adam Waller
' Date      : 7/12/2021
' Purpose   : Load the VBA standard/class module from a file through VBE. (This allows
'           : us to preserve hidden attributes not recognized in then LoadFromText
'           : import of code modules and classes.)
'---------------------------------------------------------------------------------------
'
Private Sub LoadVbeModuleFromFile(strFile As String, strName As String)

    Dim proj As VBProject
    
    If DebugMode(True) Then On Error GoTo 0 Else On Error Resume Next
    
    Set proj = GetVBProjectForCurrentDB
    Perf.OperationStart "Import VBE Module"
    With proj.VBComponents
        
        ' Remove any existing component (In most cases the module will exist)
        If DebugMode(True) Then On Error Resume Next Else On Error Resume Next
        .Remove .Item(strName)
        If DebugMode(False) Then On Error GoTo 0 Else On Error Resume Next
        
        ' Load from the file
        .Import strFile
    End With
    Perf.OperationEnd
   
    CatchAny eelError, "Error importing VBA code for " & strName, ModuleName & ".LoadVbeModuleFromFile"
    
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Merge
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Merge the source file into the existing database, updating or replacing
'           : any existing object.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Merge(strFile As String)
    DeleteObjectIfExists acModule, GetObjectNameFromFileName(strFile)
    If FSO.FileExists(strFile) Then
        IDbComponent_Import strFile
    Else
        VCSIndex.Remove Me
    End If
End Sub


'---------------------------------------------------------------------------------------
' Procedure : ExportVbComponent
' Author    : Adam Waller
' Date      : 5/26/2021
' Purpose   : Export the code module VB component
'---------------------------------------------------------------------------------------
'
Private Sub ExportVbComponent(strFile As String)
    Perf.OperationStart "Export VBE Module"
    GetVBProjectForCurrentDB.VBComponents(m_Module.Name).Export strFile
    Perf.OperationEnd
End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetAllFromDB
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a collection of class objects represented by this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetAllFromDB(Optional blnModifiedOnly As Boolean = False) As Collection
        
    Dim oMod As AccessObject
    Dim cModule As IDbComponent
    Dim proj As VBProject
    
    ' Build collection if not already cached
    If m_AllItems Is Nothing Or blnModifiedOnly <> m_blnModifiedOnly Then
        m_blnModifiedOnly = blnModifiedOnly
        Set m_AllItems = New Collection
        Set proj = GetVBProjectForCurrentDB
        For Each oMod In CurrentProject.AllModules
            Set cModule = New clsDbModule
            Set cModule.DbObject = oMod
            If blnModifiedOnly Then
                If cModule.IsModified Then m_AllItems.Add cModule, oMod.Name
            Else
                m_AllItems.Add cModule, oMod.Name
            End If
        Next oMod
    End If

    ' Return cached collection
    Set IDbComponent_GetAllFromDB = m_AllItems
        
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetFileList
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a list of file names to import for this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetFileList(Optional blnModifiedOnly As Boolean = False) As Collection
    Set IDbComponent_GetFileList = GetFilePathsInFolder(IDbComponent_BaseFolder, "*.bas")
    MergeCollection IDbComponent_GetFileList, GetFilePathsInFolder(IDbComponent_BaseFolder, "*.cls")
End Function


'---------------------------------------------------------------------------------------
' Procedure : ClearOrphanedSourceFiles
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Remove any source files for objects not in the current database.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_ClearOrphanedSourceFiles()
    ClearOrphanedSourceFiles Me, "bas", "cls"
End Sub


'---------------------------------------------------------------------------------------
' Procedure : IsModified
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Returns true if the object in the database has been modified since
'           : the last export/import of the object.
'---------------------------------------------------------------------------------------
'
Public Function IDbComponent_IsModified() As Boolean

    ' The modified date for the object changes frequently with compile/save operations,
    ' so use the hash instead to detect changes.
    
    ' NOTE: This will not detect changes to hidden VBE attributes
    IDbComponent_IsModified = VCSIndex.Item(Me)("Hash") <> GetCodeModuleHash(IDbComponent_ComponentType, m_Module.Name)

End Function


'---------------------------------------------------------------------------------------
' Procedure : DateModified
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : The date/time the object was modified. (If possible to retrieve)
'           : If the modified date cannot be determined (such as application
'           : properties) then this function will return 0.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_DateModified() As Date
    IDbComponent_DateModified = CurrentProject.AllModules(m_Module.Name).DateModified
End Function


'---------------------------------------------------------------------------------------
' Procedure : SourceModified
' Author    : Adam Waller
' Date      : 4/27/2020
' Purpose   : The date/time the source object was modified. In most cases, this would
'           : be the date/time of the source file, but it some cases like SQL objects
'           : the date can be determined through other means, so this function
'           : allows either approach to be taken.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_SourceModified() As Date
    If FSO.FileExists(IDbComponent_SourceFile) Then IDbComponent_SourceModified = GetLastModifiedDate(IDbComponent_SourceFile)
End Function


'---------------------------------------------------------------------------------------
' Procedure : Category
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a category name for this type. (I.e. forms, queries, macros)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Category() As String
    IDbComponent_Category = "Modules"
End Property


'---------------------------------------------------------------------------------------
' Procedure : BaseFolder
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the base folder for import/export of this component.
'---------------------------------------------------------------------------------------
Private Property Get IDbComponent_BaseFolder() As String
    IDbComponent_BaseFolder = Options.GetExportFolder & "modules" & PathSep
End Property


'---------------------------------------------------------------------------------------
' Procedure : Name
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a name to reference the object for use in logs and screen output.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Name() As String
    IDbComponent_Name = m_Module.Name
End Property


'---------------------------------------------------------------------------------------
' Procedure : SourceFile
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the full path of the source file for the current object.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SourceFile() As String
    IDbComponent_SourceFile = IDbComponent_BaseFolder & GetSafeFileName(m_Module.Name) & GetExtension
End Property


'---------------------------------------------------------------------------------------
' Procedure : GetExtension
' Author    : Adam Waller
' Date      : 6/4/2021
' Purpose   : Return the extension (".cls" or ".bas") based on the component type.
'---------------------------------------------------------------------------------------
'
Private Function GetExtension() As String
    If GetVBProjectForCurrentDB.VBComponents(m_Module.Name).Type = vbext_ct_StdModule Then
        GetExtension = ".bas"
    Else
        GetExtension = ".cls"
    End If
End Function


'---------------------------------------------------------------------------------------
' Procedure : Count
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a count of how many items are in this category.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Count(Optional blnModifiedOnly As Boolean = False) As Long
    IDbComponent_Count = IDbComponent_GetAllFromDB(blnModifiedOnly).Count
End Property


'---------------------------------------------------------------------------------------
' Procedure : ComponentType
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : The type of component represented by this class.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_ComponentType() As eDatabaseComponentType
    IDbComponent_ComponentType = edbModule
End Property


'---------------------------------------------------------------------------------------
' Procedure : Upgrade
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Run any version specific upgrade processes before importing.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Upgrade()
    ' No upgrade needed for modules.
End Sub


'---------------------------------------------------------------------------------------
' Procedure : SingleFile
' Author    : Adam Waller
' Date      : 4/24/2020
' Purpose   : Returns true if the export of all items is done as a single file instead
'           : of individual files for each component. (I.e. properties, references)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SingleFile() As Boolean
    IDbComponent_SingleFile = False
End Property


'---------------------------------------------------------------------------------------
' Procedure : DbObject
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This represents the database object we are dealing with.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_DbObject() As Object
    Set IDbComponent_DbObject = m_Module
End Property
Private Property Set IDbComponent_DbObject(ByVal RHS As Object)
    Set m_Module = RHS
End Property


'---------------------------------------------------------------------------------------
' Procedure : Parent
' Author    : Adam Waller
' Date      : 4/24/2020
' Purpose   : Return a reference to this class as an IDbComponent. This allows you
'           : to reference the public methods of the parent class without needing
'           : to create a new class object.
'---------------------------------------------------------------------------------------
'
Public Property Get Parent() As IDbComponent
    Set Parent = Me
End Property
