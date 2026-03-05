/// <summary>
///   Shared test utility functions and base classes.
///   Provides example file discovery and a reusable temp-directory fixture base.
/// </summary>
unit Tests.GeminiFile.TestUtils;

interface

uses
	System.SysUtils,
	DUnitX.TestFramework;

/// <summary>
///   Returns the path to the examples directory.
///   Navigates from tests/Win64/Debug/ up to project root, then into examples.
///   Falls back to relative path from working directory.
/// </summary>
function ExamplesDir: string;

/// <summary>
///   Attempts to find an example file by name. Returns empty string if not found.
/// </summary>
function FindExample(const AName: string): string;

type
	/// <summary>
	///   Base class for test fixtures that need a temporary directory.
	///   Creates a unique temp dir in Setup, removes it in TearDown.
	///   Provides helpers to write text and binary files into the temp dir.
	/// </summary>
	TTempDirTestBase = class
	protected
		FTempDir: string;
		/// <summary>Writes a UTF-8 text file into FTempDir and returns its full path.</summary>
		function CreateTempFile(const AName, AContent: string): string;
		/// <summary>Writes a binary file into FTempDir and returns its full path.</summary>
		function CreateTempFileBytes(const AName: string; const ABytes: TBytes): string;
	public
		[Setup]
		procedure Setup; virtual;
		[TearDown]
		procedure TearDown; virtual;
	end;

implementation

uses
	System.IOUtils,
	System.Classes;

function ExamplesDir: string;
begin
	Result := TPath.Combine(
		TPath.GetDirectoryName(TPath.GetDirectoryName(TPath.GetDirectoryName(
			TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)))))),
		'examples');
	if not TDirectory.Exists(Result) then
		Result := TPath.GetFullPath('..\examples');
end;

function FindExample(const AName: string): string;
begin
	Result := TPath.Combine(ExamplesDir, AName);
	if not FileExists(Result) then
	begin
		// Example files use '..gemini' extension (double dot before gemini)
		Result := TPath.Combine(ExamplesDir, AName + '..gemini');
		if not FileExists(Result) then
			Result := '';
	end;
end;

// ========================================================================
// TTempDirTestBase
// ========================================================================

procedure TTempDirTestBase.Setup;
begin
	FTempDir := TPath.Combine(TPath.GetTempPath,
		'gemini_test_' + TGUID.NewGuid.ToString);
	ForceDirectories(FTempDir);
end;

procedure TTempDirTestBase.TearDown;
begin
	if TDirectory.Exists(FTempDir) then
		TDirectory.Delete(FTempDir, True);
end;

function TTempDirTestBase.CreateTempFile(const AName, AContent: string): string;
begin
	Result := TPath.Combine(FTempDir, AName);
	TFile.WriteAllText(Result, AContent, TEncoding.UTF8);
end;

function TTempDirTestBase.CreateTempFileBytes(const AName: string; const ABytes: TBytes): string;
var
	LStream: TFileStream;
begin
	Result := TPath.Combine(FTempDir, AName);
	LStream := TFileStream.Create(Result, fmCreate);
	try
		if Length(ABytes) > 0 then
			LStream.WriteBuffer(ABytes[0], Length(ABytes));
	finally
		LStream.Free;
	end;
end;

end.
