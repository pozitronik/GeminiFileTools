/// <summary>
///   Shared interface for all conversation formatters.
///   Decouples formatter consumers from concrete implementations (DIP).
/// </summary>
unit GeminiFile.Formatter.Intf;

interface

uses
	System.Classes,
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model;

type
	/// <summary>
	///   Common interface for conversation formatters.
	///   Implemented by text, markdown, and HTML formatters.
	/// </summary>
	IGeminiFormatter = interface
		['{A7F3E8C1-4B2D-4E9A-8F1C-6D5A3B2E7F09}']
		/// <summary>
		///   Writes the formatted conversation to the output stream.
		/// </summary>
		procedure FormatToStream(
			AOutput: TStream;
			AChunks: TObjectList<TGeminiChunk>;
			const ASystemInstruction: string;
			ARunSettings: TGeminiRunSettings;
			const AResources: TArray<TFormatterResourceInfo>
		);
	end;

implementation

end.
