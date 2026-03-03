/// <summary>
///   Groups consecutive same-kind conversation chunks for block combining.
///   When combining is enabled, consecutive user/model/thinking chunks merge
///   into a single visual block with shared metadata. When disabled, each
///   chunk is its own single-element group -- preserving current behavior.
/// </summary>
unit GeminiFile.Grouping;

interface

uses
	System.Generics.Collections,
	GeminiFile.Types,
	GeminiFile.Model;

type
	/// <summary>Logical kind of a chunk for grouping purposes.</summary>
	TChunkGroupKind = (gkUser, gkModel, gkThinking);

	/// <summary>
	///   A group of consecutive chunks sharing the same kind.
	///   Chunks are borrowed references (not owned).
	/// </summary>
	TChunkGroup = record
		/// <summary>Shared kind of all chunks in this group.</summary>
		Kind: TChunkGroupKind;
		/// <summary>Ordered chunks belonging to this group.</summary>
		Chunks: TArray<TGeminiChunk>;
		/// <summary>First non-zero CreateTime found scanning forward.</summary>
		FirstCreateTime: TDateTime;
		/// <summary>Arithmetic sum of TokenCount across all chunks.</summary>
		TotalTokenCount: Integer;
	end;

	/// <summary>
	///   Determines the grouping kind of a single chunk.
	///   Thinking is keyed on IsThought (always model in practice),
	///   otherwise determined by Role.
	/// </summary>
	/// <param name="AChunk">Chunk to classify.</param>
	/// <returns>The chunk's group kind.</returns>
function GetChunkGroupKind(AChunk: TGeminiChunk): TChunkGroupKind;

/// <summary>
///   Groups consecutive same-kind chunks into an array of groups.
///   When ACombine is False, each chunk becomes a single-element group.
///   When True, consecutive same-kind chunks merge with combined metadata.
/// </summary>
/// <param name="AChunks">Ordered list of conversation chunks.</param>
/// <param name="ACombine">Whether to merge consecutive same-kind chunks.</param>
/// <returns>Array of chunk groups.</returns>
function GroupConsecutiveChunks(AChunks: TObjectList<TGeminiChunk>; ACombine: Boolean): TArray<TChunkGroup>;

implementation

function GetChunkGroupKind(AChunk: TGeminiChunk): TChunkGroupKind;
begin
	if AChunk.IsThought then
		Result := gkThinking
	else
		case AChunk.Role of
			grUser:
				Result := gkUser;
			else
				Result := gkModel;
		end;
end;

function GroupConsecutiveChunks(AChunks: TObjectList<TGeminiChunk>; ACombine: Boolean): TArray<TChunkGroup>;
var
	LGroups: TList<TChunkGroup>;
	LGroup: TChunkGroup;
	LChunkAccum: TList<TGeminiChunk>;
	LChunk: TGeminiChunk;
	LKind: TChunkGroupKind;
	I: Integer;

	/// Finalizes the current accumulator into a group record and appends it.
	procedure FlushGroup;
	begin
		if LChunkAccum.Count = 0 then
			Exit;
		LGroup.Chunks := LChunkAccum.ToArray;
		LGroups.Add(LGroup);
		LChunkAccum.Clear;
	end;

begin
	LGroups := TList<TChunkGroup>.Create;
	LChunkAccum := TList<TGeminiChunk>.Create;
	try
		for I := 0 to AChunks.Count - 1 do
		begin
			LChunk := AChunks[I];
			LKind := GetChunkGroupKind(LChunk);

			if ACombine and (LChunkAccum.Count > 0) and (LGroup.Kind = LKind) then
			begin
				// Extend current group -- O(1) list append instead of array concat
				LChunkAccum.Add(LChunk);
				Inc(LGroup.TotalTokenCount, LChunk.TokenCount);
				if (LGroup.FirstCreateTime = 0) and (LChunk.CreateTime <> 0) then
					LGroup.FirstCreateTime := LChunk.CreateTime;
			end else begin
				// Finalize previous group and start a new one
				FlushGroup;
				LGroup := Default (TChunkGroup);
				LGroup.Kind := LKind;
				LGroup.FirstCreateTime := LChunk.CreateTime;
				LGroup.TotalTokenCount := LChunk.TokenCount;
				LChunkAccum.Add(LChunk);
			end;
		end;

		FlushGroup;
		Result := LGroups.ToArray;
	finally
		LChunkAccum.Free;
		LGroups.Free;
	end;
end;

end.
