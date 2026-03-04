/// <summary>
///   Shared test utility functions for example file discovery.
///   Resolves the examples directory relative to the test executable path.
/// </summary>
unit Tests.GeminiFile.TestUtils;

interface

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

implementation

uses
	System.SysUtils,
	System.IOUtils;

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

end.
