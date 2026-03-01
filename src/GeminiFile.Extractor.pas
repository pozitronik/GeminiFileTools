/// <summary>
///   Resource extraction for Gemini conversation files (Pure Fabrication).
///   Single responsibility: extract resources from a parsed model to the filesystem.
///   Supports sequential and parallel (threaded) extraction modes.
/// </summary>
unit GeminiFile.Extractor;

interface

uses
	System.SysUtils,
	System.IOUtils,
	System.Threading,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model;

type
	/// <summary>
	///   Interface for extracting embedded resources to the filesystem.
	///   Allows substitution of extraction strategy (DIP).
	/// </summary>
	IGeminiResourceExtractor = interface
		['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
		/// <summary>
		///   Extracts all provided resources to files in the specified directory.
		///   Files are named prefix_NNN.ext where NNN is a zero-padded index.
		/// </summary>
		/// <param name="AResources">Array of resources to extract.</param>
		/// <param name="AOutputDir">Directory to write files to. Created if it does not exist.</param>
		/// <param name="AThreaded">If True, uses parallel extraction.</param>
		/// <param name="ANamePrefix">Filename prefix, e.g. 'resource'.</param>
		/// <param name="AOnProgress">Optional progress callback.</param>
		/// <returns>Number of resources extracted.</returns>
		function ExtractAll(const AResources: TArray<TGeminiResource>; const AOutputDir: string; AThreaded: Boolean; const ANamePrefix: string; AOnProgress: TGeminiExtractProgressEvent): Integer;
	end;

	/// <summary>
	///   Default resource extractor implementation.
	///   Supports sequential and parallel (TParallel.For) extraction modes.
	/// </summary>
	TGeminiResourceExtractor = class(TInterfacedObject, IGeminiResourceExtractor)
	public
		/// <summary>
		///   Extracts all provided resources to files in the specified directory.
		/// </summary>
		/// <param name="AResources">Array of resources to extract.</param>
		/// <param name="AOutputDir">Directory to write files to. Created if it does not exist.</param>
		/// <param name="AThreaded">If True, uses parallel extraction. Default True.</param>
		/// <param name="ANamePrefix">Filename prefix. Default 'resource'.</param>
		/// <param name="AOnProgress">Optional progress callback.</param>
		/// <returns>Number of resources extracted.</returns>
		function ExtractAll(const AResources: TArray<TGeminiResource>; const AOutputDir: string; AThreaded: Boolean; const ANamePrefix: string; AOnProgress: TGeminiExtractProgressEvent): Integer;
	end;

implementation

{TGeminiResourceExtractor}

function TGeminiResourceExtractor.ExtractAll(const AResources: TArray<TGeminiResource>; const AOutputDir: string; AThreaded: Boolean; const ANamePrefix: string; AOnProgress: TGeminiExtractProgressEvent): Integer;
var
	LAbsDir: string;
	I: Integer;
	LFileName: string;
	LPadWidth: Integer;
begin
	Result := Length(AResources);
	if Result = 0 then
		Exit;

	LAbsDir := TPath.GetFullPath(AOutputDir);
	ForceDirectories(LAbsDir);
	LPadWidth := Length(IntToStr(Result));
	if LPadWidth < 3 then
		LPadWidth := 3;

	if AThreaded and (Result > 1) then
	begin
		TParallel.&For(0, Result - 1,
			procedure(AIdx: Integer)
			var
				LFN: string;
			begin
				LFN := TPath.Combine(LAbsDir, Format('%s_%.*d%s', [ANamePrefix, LPadWidth, AIdx, AResources[AIdx].GetFileExtension]));
				AResources[AIdx].SaveToFile(LFN);
				if Assigned(AOnProgress) then
					AOnProgress(AIdx, Length(AResources), LFN);
			end);
	end else begin
		for I := 0 to Result - 1 do
		begin
			LFileName := TPath.Combine(LAbsDir, Format('%s_%.*d%s', [ANamePrefix, LPadWidth, I, AResources[I].GetFileExtension]));
			AResources[I].SaveToFile(LFileName);
			if Assigned(AOnProgress) then
				AOnProgress(I, Result, LFileName);
		end;
	end;
end;

end.
