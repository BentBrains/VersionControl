﻿VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsDbHiddenAttribute"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'---------------------------------------------------------------------------------------
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : This class extends the IDbComponent class to perform the specific
'           : operations required by this particular object type.
'           : (I.e. The specific way you export or import this component.)
'---------------------------------------------------------------------------------------
Option Compare Database
Option Explicit

Private Const ModuleName As String = "clsDbHiddenAttribute"

Private m_AllItems As Collection
Public m_dItems As Dictionary
Private m_Count As Long

' This requires us to use all the public methods and properties of the implemented class
' which keeps all the component classes consistent in how they are used in the export
' and import process. The implemented functions should be kept private as they are called
' from the implementing class, not this class.
Implements IDbComponent


'---------------------------------------------------------------------------------------
' Procedure : Export
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Export the individual database component (table, form, query, etc...)
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Export()
    WriteJsonFile TypeName(Me), m_dItems, IDbComponent_SourceFile, "Database objects hidden attribute"
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Import
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Import the individual database component from a file.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Import(strFile As String)

    Dim dFile As Dictionary
    Dim dItems As Dictionary
    Dim dbs As Database
    Dim varCont As Variant
    Dim varDoc As Variant
    Dim objType As AcObjectType

    ' Only import files with the correct extension.
    If Not strFile Like "*.json" Then Exit Sub

    If DebugMode(True) Then On Error GoTo 0 Else On Error Resume Next
    
    Set dFile = ReadJsonFile(strFile)
    If Not dFile Is Nothing Then
        Set dbs = CurrentDb
        Set dItems = dFile("Items")
        For Each varCont In dItems.Keys
            objType = GetObjectTypeFromContainer(dbs.Containers(varCont))
            If objType <> acDefault Then
                For Each varDoc In dItems(varCont)
                    ' Set object to hidden
                    Application.SetHiddenAttribute objType, varDoc, True
                    CatchAny eelError, "Error setting hidden attribute for " & varDoc, ModuleName
                Next varDoc
            End If
        Next varCont
    End If
    
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

End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetAllFromDB
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return a collection of class objects represented by this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetAllFromDB(Optional blnModifiedOnly As Boolean = False) As Collection
    
    Dim cDoc As IDbComponent
    Dim dCont As Dictionary
    Dim cont As DAO.Container
    Dim doc As DAO.Document
    Dim dbs As Database
    Dim contType As AcObjectType
    Dim colItems As Collection
    
    ' Build collection if not already cached
    If m_AllItems Is Nothing Then

        Set m_AllItems = New Collection
        Set m_dItems = New Dictionary
        Set dbs = CurrentDb
        m_Count = 0
        
        ' Loop through all the containers, documents, and check hidden property
        For Each cont In dbs.Containers
            Set dCont = New Dictionary
            Set dCont = New Dictionary
            Set colItems = New Collection
            contType = GetObjectTypeFromContainer(cont)
            For Each doc In cont.Documents
                If contType <> acDefault _
                    And Not (contType = acTable _
                    And (doc.Name Like "MSys*" Or doc.Name Like "~*")) Then
                    ' Check Hidden Attribute property (only exposed here)
                    If Application.GetHiddenAttribute(contType, doc.Name) Then
                        ' Add to collection of hidden item item names of this type.
                        colItems.Add doc.Name
                        ' Add to collection of all items
                        Set cDoc = Me
                        m_AllItems.Add cDoc
                    End If
                End If
            Next doc
            If colItems.Count > 0 Then m_dItems.Add cont.Name, SortCollectionByValue(colItems)
        Next cont
        
    End If

    ' Return cached collection
    Set IDbComponent_GetAllFromDB = m_AllItems
        
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetObjectTypeFromContainer
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Get an object type from a DAO container
'---------------------------------------------------------------------------------------
'
Private Function GetObjectTypeFromContainer(ByRef cont As DAO.Container) As AcObjectType
    Select Case cont.Name
        Case "Tables"
            GetObjectTypeFromContainer = acTable
        Case "Forms"
            GetObjectTypeFromContainer = acForm
        Case "Scripts"
            GetObjectTypeFromContainer = acMacro
        Case "Queries"
            GetObjectTypeFromContainer = acQuery
        Case "Reports"
            GetObjectTypeFromContainer = acReport
        Case "Modules"
            GetObjectTypeFromContainer = acModule
        Case Else
            ' Unknown
            GetObjectTypeFromContainer = acDefault
    End Select
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetFileList
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return a list of file names to import for this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetFileList(Optional blnModifiedOnly As Boolean = False) As Collection
    Set IDbComponent_GetFileList = New Collection
    If FSO.FileExists(IDbComponent_SourceFile) Then IDbComponent_GetFileList.Add IDbComponent_SourceFile
End Function


'---------------------------------------------------------------------------------------
' Procedure : ClearOrphanedSourceFiles
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Remove any source files for objects not in the current database.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_ClearOrphanedSourceFiles()
    If FSO.FileExists(IDbComponent_SourceFile) Then
        If IDbComponent_GetAllFromDB.Count = 0 Then
            ' Remove existing file, since we don't have any hidden objects.
            DeleteFile IDbComponent_SourceFile
        End If
    End If
End Sub


'---------------------------------------------------------------------------------------
' Procedure : IsModified
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Returns true if the object in the database has been modified since
'           : the last export of the object.
'---------------------------------------------------------------------------------------
'
Public Function IDbComponent_IsModified() As Boolean

End Function


'---------------------------------------------------------------------------------------
' Procedure : DateModified
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : The date/time the object was modified. (If possible to retrieve)
'           : If the modified date cannot be determined (such as application
'           : properties) then this function will return 0.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_DateModified() As Date
    ' Modified date unknown.
    IDbComponent_DateModified = 0
End Function


'---------------------------------------------------------------------------------------
' Procedure : SourceModified
' Author    : Adam Waller / Indigo744
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
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return a category name for this type. (I.e. forms, queries, macros)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Category() As String
    IDbComponent_Category = "Hidden Attributes"
End Property


'---------------------------------------------------------------------------------------
' Procedure : BaseFolder
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return the base folder for import/export of this component.
'---------------------------------------------------------------------------------------
Private Property Get IDbComponent_BaseFolder() As String
    IDbComponent_BaseFolder = Options.GetExportFolder
End Property


'---------------------------------------------------------------------------------------
' Procedure : Name
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return a name to reference the object for use in logs and screen output.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Name() As String
    IDbComponent_Name = "Database hidden attributes"
End Property


'---------------------------------------------------------------------------------------
' Procedure : SourceFile
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return the full path of the source file for the current object.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SourceFile() As String
    IDbComponent_SourceFile = IDbComponent_BaseFolder & "hidden-attributes.json"
End Property


'---------------------------------------------------------------------------------------
' Procedure : Count
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Return a count of how many items are in this category.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Count(Optional blnModifiedOnly As Boolean = False) As Long
    IDbComponent_Count = IDbComponent_GetAllFromDB(blnModifiedOnly).Count
End Property


'---------------------------------------------------------------------------------------
' Procedure : ComponentType
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : The type of component represented by this class.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_ComponentType() As eDatabaseComponentType
    IDbComponent_ComponentType = edbHiddenAttribute
End Property


'---------------------------------------------------------------------------------------
' Procedure : Upgrade
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : Run any version specific upgrade processes before importing.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Upgrade()
    ' No upgrade needed.
End Sub


'---------------------------------------------------------------------------------------
' Procedure : DbObject
' Author    : Adam Waller / Indigo744
' Date      : 11/14/2020
' Purpose   : This represents the database object we are dealing with.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_DbObject() As Object
    Set IDbComponent_DbObject = Nothing
End Property
Private Property Set IDbComponent_DbObject(ByVal RHS As Object)
End Property


'---------------------------------------------------------------------------------------
' Procedure : SingleFile
' Author    : Adam Waller / Indigo744
' Date      : 4/24/2020
' Purpose   : Returns true if the export of all items is done as a single file instead
'           : of individual files for each component. (I.e. properties, references)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SingleFile() As Boolean
    IDbComponent_SingleFile = True
End Property


'---------------------------------------------------------------------------------------
' Procedure : Parent
' Author    : Adam Waller / Indigo744
' Date      : 4/24/2020
' Purpose   : Return a reference to this class as an IDbComponent. This allows you
'           : to reference the public methods of the parent class without needing
'           : to create a new class object.
'---------------------------------------------------------------------------------------
'
Public Property Get Parent() As IDbComponent
    Set Parent = Me
End Property

