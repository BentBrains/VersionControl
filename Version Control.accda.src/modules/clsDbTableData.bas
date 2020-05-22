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

Public Format As eTableDataExportFormat

Private m_Table As AccessObject
Private m_AllItems As Collection

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
    
    Dim strFile As String
    Dim intFormat As eTableDataExportFormat

    ' Make sure the path exists.
    VerifyPath FSO.GetParentFolderName(IDbComponent_SourceFile)

    ' Save as selected format, and remove other formats if they exist.
    For intFormat = 1 To eTableDataExportFormat.[_Last]
        ' Build file name for this format
        strFile = IDbComponent_BaseFolder & GetSafeFileName(m_Table.Name) & "." & GetExtByFormat(intFormat)
        If FSO.FileExists(strFile) Then Kill strFile
        If intFormat = Me.Format Then
            ' Export the table using this format.
            Select Case intFormat
                Case etdTabDelimited:   ExportTableDataAsTDF m_Table.Name
                Case etdXML:
                    Application.ExportXML acExportTable, m_Table.Name, strFile
                    SanitizeXML strFile, Options
            End Select
        End If
    Next intFormat
    
End Sub


'---------------------------------------------------------------------------------------
' Procedure : ExportTableData
' Author    : Adam Waller
' Date      : 1/18/2019
' Purpose   : Export the data from the table.
'---------------------------------------------------------------------------------------
'
Public Sub ExportTableDataAsTDF(strTable As String)

    Dim rst As DAO.Recordset
    Dim fld As DAO.Field
    Dim cData As New clsConcat
    Dim intFields As Integer
    Dim intCnt As Integer
    Dim strText As String

    ' Open table in fast read-only view
    Set rst = CurrentDb.OpenRecordset(GetTableExportSql(strTable), dbOpenSnapshot, dbOpenForwardOnly)
    intFields = rst.Fields.Count

    ' Add header row
    For Each fld In rst.Fields
        cData.Add fld.Name
        intCnt = intCnt + 1
        If intCnt < intFields Then cData.Add vbTab
    Next fld
    cData.Add vbCrLf

    ' Add data rows
    Do While Not rst.EOF
        intCnt = 0
        For Each fld In rst.Fields
            ' Format for TDF format without line breaks
            strText = MultiReplace(Nz(fld.Value), "\", "\\", vbCrLf, "\r\n", vbCr, "\r", vbLf, "\n", vbTab, "\t")
            cData.Add strText
            intCnt = intCnt + 1
            If intCnt < intFields Then cData.Add vbTab
        Next fld
        cData.Add vbCrLf
        rst.MoveNext
        Log.Increment ' Increment log, in case this takes a while
    Loop

    ' Save output file
    WriteFile cData.GetStr, IDbComponent_BaseFolder & GetSafeFileName(StripDboPrefix(strTable)) & ".txt"

End Sub


'---------------------------------------------------------------------------------------
' Procedure : ImportTableDataTDF
' Author    : Adam Waller
' Date      : 5/7/2020
' Purpose   : Imports the data from a TDF file, loading it into the table
'---------------------------------------------------------------------------------------
'
Private Sub ImportTableDataTDF(strFile As String)

    Dim strTable As String
    Dim dCols As Dictionary
    Dim fld As DAO.Field
    Dim dbs As DAO.Database
    Dim rst As Recordset
    Dim stm As Scripting.TextStream
    Dim strLine As String
    Dim varLine As Variant
    Dim varHeader As Variant
    Dim intCol As Integer
    Dim strValue As String
    
    ' Build a dictionary of column names so we can load the data
    ' into the matching columns.
    strTable = GetObjectNameFromFileName(strFile)
    Set dbs = CurrentDb
    Set dCols = New Dictionary
    For Each fld In dbs.TableDefs(strTable).Fields
        dCols.Add fld.Name, fld.Name
    Next fld
    
    ' Clear any existing records before importing this data.
    dbs.Execute "delete from " & strTable, dbFailOnError
    Set rst = dbs.OpenRecordset(strTable)
    
    ' Read file line by line
    Set stm = FSO.OpenTextFile(strFile)
    Set rst = dbs.OpenRecordset(strTable)
    Do While Not stm.AtEndOfStream
        strLine = stm.ReadLine
        If Not IsArray(varHeader) Then
            ' Read header line
            varHeader = Split(strLine, vbTab)
        Else
            ' Data line
            varLine = Split(strLine, vbTab)
            rst.AddNew
                ' Loop through fields
                For intCol = 0 To UBound(varHeader)
                    ' Check to see if field exists in the table
                    If dCols.Exists(varHeader(intCol)) Then
                        ' Perform any needed replacements
                        strValue = MultiReplace(CStr(varLine(intCol)), _
                            "\\", "\", "\r\n", vbCrLf, "\r", vbCr, "\n", vbLf, "\t", vbTab)
                        If strValue <> CStr(varLine(intCol)) Then
                            ' Use replaced string value
                            rst.Fields(varHeader(intCol)).Value = strValue
                        Else
                            ' Use variant value without the string conversion
                            rst.Fields(varHeader(intCol)).Value = varLine(intCol)
                        End If
                    End If
                Next intCol
            rst.Update
        End If
        ' Increment log, just in case this takes a while.
        Log.Increment
    Loop
    stm.Close
    Set stm = Nothing
    rst.Close
    Set rst = Nothing
    
End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetTableExportSql
' Author    : Adam Waller
' Date      : 1/18/2019
' Purpose   : Build SQL to export `tbl_name` sorted by each field from first to last
'---------------------------------------------------------------------------------------
'
Private Function GetTableExportSql(strTable As String) As String

    Dim tdf As DAO.TableDef
    Dim fld As DAO.Field
    Dim intCnt As Integer
    Dim intFields As Integer
    Dim cText As New clsConcat
    Dim cFieldList As New clsConcat
    Dim dbs As Database

    Set dbs = CurrentDb
    Set tdf = dbs.TableDefs(strTable)
    intFields = tdf.Fields.Count

    ' Build list of fields
    With cFieldList
        For Each fld In tdf.Fields
            .Add "["
            .Add fld.Name
            .Add "]"
            intCnt = intCnt + 1
            If intCnt < intFields Then .Add ", "
        Next fld
    End With

    ' Build select statement
    With cText
        .Add "SELECT "
        .Add cFieldList.GetStr
        .Add " FROM ["
        .Add strTable
        .Add "] ORDER BY "
        .Add cFieldList.GetStr
    End With

    GetTableExportSql = cText.GetStr

End Function


'---------------------------------------------------------------------------------------
' Procedure : Import
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Import the table data from a file.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Import(strFile As String)

    Dim strTable As String

    ' Import from different formats (XML is preferred for data integrity)
    Select Case GetFormatByExt(strFile)
        Case etdXML
            strTable = GetObjectNameFromFileName(strFile)
            If TableExists(strTable) Then DoCmd.DeleteObject acTable, strTable
            Application.ImportXML strFile, acStructureAndData
        Case etdTabDelimited
            ImportTableDataTDF strFile
    End Select

End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetAllFromDB
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a collection of class objects represented by this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetAllFromDB() As Collection
    
    Dim tbl As AccessObject
    Dim cTable As clsDbTableData
    Dim cComponent As IDbComponent
    
    ' Build collection if not already cached
    If m_AllItems Is Nothing Then
        Set m_AllItems = New Collection
        
        ' No need to go any further if we don't have any saved tables defined
        If Options.TablesToExportData.Count > 0 Then
            
            ' We have at least one table defined. Loop through the tables looking
            ' for a matching name.
            With Options
                For Each tbl In CurrentData.AllTables
                    If .TablesToExportData.Exists(tbl.Name) Then
                        Set cTable = New clsDbTableData
                        cTable.Format = .GetTableExportFormat(CStr(.TablesToExportData(tbl.Name)("Format")))
                        Set cComponent = cTable
                        Set cComponent.DbObject = tbl
                        m_AllItems.Add cComponent, tbl.Name
                    End If
                Next tbl
            End With
        End If
    End If

    ' Return cached collection
    Set IDbComponent_GetAllFromDB = m_AllItems
        
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetFileList
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a list of file names to import for this component type. (Could be
'           : a couple different file extensions involved.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetFileList() As Collection
    Dim colFiles As Collection
    Set colFiles = GetFilePathsInFolder(IDbComponent_BaseFolder & "*." & GetExtByFormat(etdTabDelimited))
    MergeCollection colFiles, GetFilePathsInFolder(IDbComponent_BaseFolder & "*." & GetExtByFormat(etdXML))
    Set IDbComponent_GetFileList = colFiles
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetExtByFormat
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the expected file extension by format.
'---------------------------------------------------------------------------------------
'
Private Function GetExtByFormat(intFormat As eTableDataExportFormat) As String
    Select Case intFormat
        Case etdTabDelimited:   GetExtByFormat = "txt"
        Case etdXML:            GetExtByFormat = "xml"
    End Select
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetFormatByExt
' Author    : Adam Waller
' Date      : 5/7/2020
' Purpose   : Look up the format from the extension name
'---------------------------------------------------------------------------------------
'
Private Function GetFormatByExt(strFile As String) As eTableDataExportFormat
    Select Case FSO.GetExtensionName(strFile)
        Case "txt": GetFormatByExt = etdTabDelimited
        Case "xml": GetFormatByExt = etdXML
    End Select
End Function


'---------------------------------------------------------------------------------------
' Procedure : ClearOrphanedSourceFiles
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Remove any source files for objects not in the current database.
'           : Note that alternate formats may stay here till the next export.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_ClearOrphanedSourceFiles() As Variant
    ClearOrphanedSourceFiles Me, "xml", "txt"
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
    IDbComponent_DateModified = m_Table.DateModified
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
    If FSO.FileExists(IDbComponent_SourceFile) Then IDbComponent_SourceModified = FileDateTime(IDbComponent_SourceFile)
End Function


'---------------------------------------------------------------------------------------
' Procedure : Category
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a category name for this type. (I.e. forms, queries, macros)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Category() As String
    IDbComponent_Category = "table data"
End Property


'---------------------------------------------------------------------------------------
' Procedure : BaseFolder
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the base folder for import/export of this component.
'---------------------------------------------------------------------------------------
Private Property Get IDbComponent_BaseFolder() As String
    IDbComponent_BaseFolder = Options.GetExportFolder & "tables\"
End Property


'---------------------------------------------------------------------------------------
' Procedure : Name
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a name to reference the object for use in logs and screen output.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Name() As String
    IDbComponent_Name = m_Table.Name
End Property


'---------------------------------------------------------------------------------------
' Procedure : SourceFile
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the full path of the source file for the current object.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SourceFile() As String
    IDbComponent_SourceFile = IDbComponent_BaseFolder & GetSafeFileName(m_Table.Name) & "." & GetExtByFormat(Me.Format)
End Property


'---------------------------------------------------------------------------------------
' Procedure : Count
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a count of how many items are in this category.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Count() As Long
    IDbComponent_Count = IDbComponent_GetAllFromDB.Count
End Property


'---------------------------------------------------------------------------------------
' Procedure : ComponentType
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : The type of component represented by this class.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_ComponentType() As eDatabaseComponentType
    IDbComponent_ComponentType = edbTableData
End Property


'---------------------------------------------------------------------------------------
' Procedure : Upgrade
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Run any version specific upgrade processes before importing.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Upgrade()
    ' No upgrade needed.
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
End Property


'---------------------------------------------------------------------------------------
' Procedure : DbObject
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This represents the database object we are dealing with.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_DbObject() As Object
    Set IDbComponent_DbObject = m_Table
End Property
Private Property Set IDbComponent_DbObject(ByVal RHS As Object)
    Set m_Table = RHS
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