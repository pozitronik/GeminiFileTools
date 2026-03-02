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
		['{29590909-9D33-42EF-8327-35B1651B8C19}']
		/// <summary>
		///   Writes the formatted conversation to the output stream.
		/// </summary>
		procedure FormatToStream(AOutput: TStream; AChunks: TObjectList<TGeminiChunk>; const ASystemInstruction: string; ARunSettings: TGeminiRunSettings; const AResources: TArray<TFormatterResourceInfo>);
	end;

implementation

end.
