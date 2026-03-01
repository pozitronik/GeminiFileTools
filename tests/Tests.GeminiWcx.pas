/// <summary>
///   Unit tests for WCX plugin logic (TGeminiArchive).
///   Tests virtual file list, header iteration, and file extraction.
///   Directly tests the class -- no DLL loading required.
/// </summary>
unit Tests.GeminiWcx;

interface

uses
	System.SysUtils,
	System.Classes,
	System.IOUtils,
	System.Types,
	System.Generics.Collections,
	DUnitX.TestFramework,
	WcxApi,
	GeminiWcx,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Parser,
	GeminiFile.Extractor,
	GeminiFile;

type
	[TestFixture]
	TTestGeminiWcxVirtualFileList = class
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
	public
		[Test]
		procedure FileWithNoResources_ThreeVirtualFiles;
		[Test]
		procedure FileWithResources_IncludesAllTypes;
		[Test]
		procedure ResourceFilenames_FollowNamingPattern;
		[Test]
		procedure FileSizes_NonZeroForAllEntries;
		[Test]
		procedure FileTime_SetFromSourceFile;
	end;

	[TestFixture]
	TTestGeminiWcxReadHeader = class
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
	public
		[Test]
		procedure IteratesAllFiles_ThenEndArchive;
		[Test]
		procedure HeaderFields_PopulatedCorrectly;
		[Test]
		procedure DirectoryEntry_HasDirectoryAttribute;
	end;

	[TestFixture]
	TTestGeminiWcxProcessFile = class
	private
		function ExamplesDir: string;
		function FindExample(const AName: string): string;
	public
		[Test]
		procedure Skip_AdvancesToNextFile;
		[Test]
		procedure ExtractTextFile_WritesCorrectContent;
		[Test]
		procedure ExtractResource_WritesDecodedBinary;
		[Test]
		procedure ExtractToInvalidPath_ReturnsError;
	end;

implementation

// Shared helpers for finding example files

function TTestGeminiWcxVirtualFileList.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxVirtualFileList.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

function TTestGeminiWcxReadHeader.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxReadHeader.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

function TTestGeminiWcxProcessFile.ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function TTestGeminiWcxProcessFile.FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
		Result := '';
end;

// ========================================================================
// TTestGeminiWcxVirtualFileList
// ========================================================================

procedure TTestGeminiWcxVirtualFileList.FileWithNoResources_ThreeVirtualFiles;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LCount: Integer;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LCount := 0;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			Inc(LCount);
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		// No resources: conversation.txt, conversation.md, conversation.html
		Assert.AreEqual<Integer>(3, LCount, 'Should have 3 virtual files for no-resource file');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileWithResources_IncludesAllTypes;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LCount: Integer;
	LPath: string;
	LHasDir, LHasEmbedded: Boolean;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LCount := 0;
		LHasDir := False;
		LHasEmbedded := False;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			Inc(LCount);
			LFileName := LHeader.FileName;
			if LFileName = 'resources' then
				LHasDir := True;
			if LFileName = 'conversation_full.html' then
				LHasEmbedded := True;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		// 3 conversations + embedded html + resources dir + 4 resources = 9
		Assert.AreEqual<Integer>(9, LCount, 'Should have 9 virtual files');
		Assert.IsTrue(LHasDir, 'Should have resources directory');
		Assert.IsTrue(LHasEmbedded, 'Should have embedded HTML');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.ResourceFilenames_FollowNamingPattern;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
	LFoundResource: Boolean;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		LFoundResource := False;
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.StartsWith('resources\resource_') then
			begin
				LFoundResource := True;
				Assert.IsTrue(LFileName.EndsWith('.jpg') or LFileName.EndsWith('.png') or
					LFileName.EndsWith('.bin'),
					'Resource should have valid extension: ' + LFileName);
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.IsTrue(LFoundResource, 'Should find at least one resource file');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileSizes_NonZeroForAllEntries;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
	LSize: Int64;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			LSize := Int64(LHeader.UnpSize) or (Int64(LHeader.UnpSizeHigh) shl 32);
			Assert.IsTrue(LSize > 0, 'Size should be > 0 for ' + LFileName);
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxVirtualFileList.FileTime_SetFromSourceFile;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		if LArchive.ReadNextHeader(LHeader) = 0 then
		begin
			Assert.IsTrue(LHeader.FileTime > 0,
				'FileTime should be set from source file modification time');
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
	finally
		LArchive.Free;
	end;
end;

// ========================================================================
// TTestGeminiWcxReadHeader
// ========================================================================

procedure TTestGeminiWcxReadHeader.IteratesAllFiles_ThenEndArchive;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LResult: Integer;
	LPath: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		// Skip all files
		while LArchive.ReadNextHeader(LHeader) = 0 do
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		// Next call should return E_END_ARCHIVE
		LResult := LArchive.ReadNextHeader(LHeader);
		Assert.AreEqual<Integer>(E_END_ARCHIVE, LResult);
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxReadHeader.HeaderFields_PopulatedCorrectly;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('conversation.txt', LFileName);
		Assert.IsTrue(LHeader.UnpSize > 0, 'UnpSize should be non-zero');
		Assert.IsTrue(LHeader.FileTime > 0, 'FileTime should be non-zero');
		Assert.AreEqual<Integer>($20, LHeader.FileAttr); // FILE_ATTRIBUTE_ARCHIVE
		LArchive.ProcessCurrentFile(PK_SKIP, '', '');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxReadHeader.DirectoryEntry_HasDirectoryAttribute;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName = 'resources' then
			begin
				Assert.AreEqual<Integer>(faDirectory, LHeader.FileAttr,
					'Directory entry should have faDirectory attribute');
				LArchive.ProcessCurrentFile(PK_SKIP, '', '');
				Exit;
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('resources directory entry not found');
	finally
		LArchive.Free;
	end;
end;

// ========================================================================
// TTestGeminiWcxProcessFile
// ========================================================================

procedure TTestGeminiWcxProcessFile.Skip_AdvancesToNextFile;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LFileName: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_LIST);
	try
		// Read first header
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('conversation.txt', LFileName);

		// Skip it
		Assert.AreEqual<Integer>(0, LArchive.ProcessCurrentFile(PK_SKIP, '', ''));

		// Read next header -- should be different file
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		LFileName := LHeader.FileName;
		Assert.AreEqual('conversation.md', LFileName);
		LArchive.ProcessCurrentFile(PK_SKIP, '', '');
	finally
		LArchive.Free;
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractTextFile_WritesCorrectContent;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir, LOutFile: string;
	LContent: string;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_Wcx_' + TGUID.NewGuid.ToString);
	LOutFile := TPath.Combine(LOutDir, 'conversation.txt');

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		// Read first header (conversation.txt)
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));

		// Extract it
		Assert.AreEqual<Integer>(0, LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
		Assert.IsTrue(FileExists(LOutFile), 'Output file should exist');

		LContent := TFile.ReadAllText(LOutFile, TEncoding.UTF8);
		Assert.Contains(LContent, '=== Gemini Conversation ===');
		Assert.Contains(LContent, 'models/gemini-2.5-pro');
	finally
		LArchive.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractResource_WritesDecodedBinary;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath, LOutDir, LOutFile: string;
	LFileName: string;
	LFileSize: Int64;
begin
	LPath := FindExample('Gadget Hackwrench In Tulle Dress');
	if LPath = '' then
		Exit;

	LOutDir := TPath.Combine(TPath.GetTempPath,
		'GemViewTest_WcxRes_' + TGUID.NewGuid.ToString);

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		// Skip until we find a resource file
		while LArchive.ReadNextHeader(LHeader) = 0 do
		begin
			LFileName := LHeader.FileName;
			if LFileName.StartsWith('resources\resource_') then
			begin
				LOutFile := TPath.Combine(LOutDir, ExtractFileName(LFileName));
				Assert.AreEqual<Integer>(0,
					LArchive.ProcessCurrentFile(PK_EXTRACT, '', LOutFile));
				Assert.IsTrue(FileExists(LOutFile), 'Extracted resource should exist');
				LFileSize := TFile.GetSize(LOutFile);
				Assert.IsTrue(LFileSize > 0, 'Extracted resource should be non-empty');
				Exit; // Only need to test one
			end;
			LArchive.ProcessCurrentFile(PK_SKIP, '', '');
		end;
		Assert.Fail('No resource file found to extract');
	finally
		LArchive.Free;
		if TDirectory.Exists(LOutDir) then
			TDirectory.Delete(LOutDir, True);
	end;
end;

procedure TTestGeminiWcxProcessFile.ExtractToInvalidPath_ReturnsError;
var
	LArchive: TGeminiArchive;
	LHeader: THeaderDataExW;
	LPath: string;
	LResult: Integer;
begin
	LPath := FindExample('Tailscale');
	if LPath = '' then
		Exit;

	LArchive := TGeminiArchive.Create(LPath, PK_OM_EXTRACT);
	try
		Assert.AreEqual<Integer>(0, LArchive.ReadNextHeader(LHeader));
		// Empty destination should return error
		LResult := LArchive.ProcessCurrentFile(PK_EXTRACT, '', '');
		Assert.IsTrue(LResult <> 0, 'Should return error for empty destination');
	finally
		LArchive.Free;
	end;
end;

initialization
	TDUnitX.RegisterTestFixture(TTestGeminiWcxVirtualFileList);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxReadHeader);
	TDUnitX.RegisterTestFixture(TTestGeminiWcxProcessFile);

end.
