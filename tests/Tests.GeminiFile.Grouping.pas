/// <summary>
///   Unit tests for the chunk grouping logic used by block combining.
///   Tests both GetChunkGroupKind classification and GroupConsecutiveChunks
///   grouping with combine enabled/disabled.
/// </summary>
unit Tests.GeminiFile.Grouping;

interface

uses
	System.SysUtils,
	System.Generics.Collections,
	DUnitX.TestFramework,
	GeminiFile.Types,
	GeminiFile.Model,
	GeminiFile.Grouping;

type
	[TestFixture]
	TTestGetChunkGroupKind = class
	private
		function MakeChunk(ARole: TGeminiRole; AIsThought: Boolean): TGeminiChunk;
	public
		[Test]
		procedure UserChunk_ReturnsUser;
		[Test]
		procedure ModelChunk_ReturnsModel;
		[Test]
		procedure ThinkingChunk_ReturnsThinking;
	end;

	[TestFixture]
	TTestGroupConsecutiveChunks = class
	private
		FChunks: TObjectList<TGeminiChunk>;
		function MakeChunk(ARole: TGeminiRole; const AText: string;
			ATokenCount: Integer = 0; AIsThought: Boolean = False;
			ACreateTime: TDateTime = 0): TGeminiChunk;
	public
		[Setup]
		procedure Setup;
		[TearDown]
		procedure TearDown;

		[Test]
		procedure CombineFalse_EachChunkSeparateGroup;
		[Test]
		procedure CombineTrue_ConsecutiveUserChunks_Merged;
		[Test]
		procedure CombineTrue_ConsecutiveModelChunks_Merged;
		[Test]
		procedure CombineTrue_ConsecutiveThinkingChunks_Merged;
		[Test]
		procedure CombineTrue_MixedSequence_CorrectGroupCount;
		[Test]
		procedure CombineTrue_ThinkingBreaksModelSequence;
		[Test]
		procedure CombineTrue_FirstCreateTime_UsesFirstNonZero;
		[Test]
		procedure CombineTrue_TotalTokenCount_SumsAll;
		[Test]
		procedure CombineTrue_EmptyList_EmptyResult;
		[Test]
		procedure CombineTrue_SingleChunk_SingleGroup;
	end;

implementation

// ========================================================================
// TTestGetChunkGroupKind
// ========================================================================

function TTestGetChunkGroupKind.MakeChunk(ARole: TGeminiRole;
	AIsThought: Boolean): TGeminiChunk;
begin
	Result := TGeminiChunk.Create;
	Result.Role := ARole;
	Result.IsThought := AIsThought;
end;

procedure TTestGetChunkGroupKind.UserChunk_ReturnsUser;
var
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grUser, False);
	try
		Assert.AreEqual<TChunkGroupKind>(gkUser, GetChunkGroupKind(LChunk));
	finally
		LChunk.Free;
	end;
end;

procedure TTestGetChunkGroupKind.ModelChunk_ReturnsModel;
var
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grModel, False);
	try
		Assert.AreEqual<TChunkGroupKind>(gkModel, GetChunkGroupKind(LChunk));
	finally
		LChunk.Free;
	end;
end;

procedure TTestGetChunkGroupKind.ThinkingChunk_ReturnsThinking;
var
	LChunk: TGeminiChunk;
begin
	LChunk := MakeChunk(grModel, True);
	try
		Assert.AreEqual<TChunkGroupKind>(gkThinking, GetChunkGroupKind(LChunk));
	finally
		LChunk.Free;
	end;
end;

// ========================================================================
// TTestGroupConsecutiveChunks
// ========================================================================

procedure TTestGroupConsecutiveChunks.Setup;
begin
	FChunks := TObjectList<TGeminiChunk>.Create(True);
end;

procedure TTestGroupConsecutiveChunks.TearDown;
begin
	FChunks.Free;
end;

function TTestGroupConsecutiveChunks.MakeChunk(ARole: TGeminiRole;
	const AText: string; ATokenCount: Integer; AIsThought: Boolean;
	ACreateTime: TDateTime): TGeminiChunk;
begin
	Result := TGeminiChunk.Create;
	Result.Role := ARole;
	Result.Text := AText;
	Result.TokenCount := ATokenCount;
	Result.IsThought := AIsThought;
	Result.CreateTime := ACreateTime;
	Result.Index := FChunks.Count;
end;

procedure TTestGroupConsecutiveChunks.CombineFalse_EachChunkSeparateGroup;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grUser, 'A'));
	FChunks.Add(MakeChunk(grUser, 'B'));
	FChunks.Add(MakeChunk(grModel, 'C'));
	LGroups := GroupConsecutiveChunks(FChunks, False);
	Assert.AreEqual<Integer>(3, Length(LGroups),
		'CombineFalse should produce one group per chunk');
	Assert.AreEqual<Integer>(1, Length(LGroups[0].Chunks));
	Assert.AreEqual<Integer>(1, Length(LGroups[1].Chunks));
	Assert.AreEqual<Integer>(1, Length(LGroups[2].Chunks));
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_ConsecutiveUserChunks_Merged;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grUser, 'A'));
	FChunks.Add(MakeChunk(grUser, 'B'));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<TChunkGroupKind>(gkUser, LGroups[0].Kind);
	Assert.AreEqual<Integer>(2, Length(LGroups[0].Chunks));
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_ConsecutiveModelChunks_Merged;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grModel, 'A'));
	FChunks.Add(MakeChunk(grModel, 'B'));
	FChunks.Add(MakeChunk(grModel, 'C'));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<TChunkGroupKind>(gkModel, LGroups[0].Kind);
	Assert.AreEqual<Integer>(3, Length(LGroups[0].Chunks));
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_ConsecutiveThinkingChunks_Merged;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grModel, 'A', 0, True));
	FChunks.Add(MakeChunk(grModel, 'B', 0, True));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<TChunkGroupKind>(gkThinking, LGroups[0].Kind);
	Assert.AreEqual<Integer>(2, Length(LGroups[0].Chunks));
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_MixedSequence_CorrectGroupCount;
var
	LGroups: TArray<TChunkGroup>;
begin
	// user, user, model, thinking, model -> 4 groups
	FChunks.Add(MakeChunk(grUser, 'A'));
	FChunks.Add(MakeChunk(grUser, 'B'));
	FChunks.Add(MakeChunk(grModel, 'C'));
	FChunks.Add(MakeChunk(grModel, 'D', 0, True));
	FChunks.Add(MakeChunk(grModel, 'E'));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(4, Length(LGroups));
	Assert.AreEqual<TChunkGroupKind>(gkUser, LGroups[0].Kind);
	Assert.AreEqual<TChunkGroupKind>(gkModel, LGroups[1].Kind);
	Assert.AreEqual<TChunkGroupKind>(gkThinking, LGroups[2].Kind);
	Assert.AreEqual<TChunkGroupKind>(gkModel, LGroups[3].Kind);
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_ThinkingBreaksModelSequence;
var
	LGroups: TArray<TChunkGroup>;
begin
	// model, thinking, model -> 3 groups
	FChunks.Add(MakeChunk(grModel, 'A'));
	FChunks.Add(MakeChunk(grModel, 'B', 0, True));
	FChunks.Add(MakeChunk(grModel, 'C'));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(3, Length(LGroups));
	Assert.AreEqual<TChunkGroupKind>(gkModel, LGroups[0].Kind);
	Assert.AreEqual<TChunkGroupKind>(gkThinking, LGroups[1].Kind);
	Assert.AreEqual<TChunkGroupKind>(gkModel, LGroups[2].Kind);
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_FirstCreateTime_UsesFirstNonZero;
var
	LGroups: TArray<TChunkGroup>;
	LTime: TDateTime;
begin
	LTime := EncodeDate(2026, 3, 1) + EncodeTime(12, 0, 0, 0);
	// First chunk has no time, second has time
	FChunks.Add(MakeChunk(grUser, 'A', 0, False, 0));
	FChunks.Add(MakeChunk(grUser, 'B', 0, False, LTime));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<TDateTime>(LTime, LGroups[0].FirstCreateTime,
		'FirstCreateTime should be the first non-zero value');
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_TotalTokenCount_SumsAll;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grModel, 'A', 10));
	FChunks.Add(MakeChunk(grModel, 'B', 20));
	FChunks.Add(MakeChunk(grModel, 'C', 5));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<Integer>(35, LGroups[0].TotalTokenCount);
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_EmptyList_EmptyResult;
var
	LGroups: TArray<TChunkGroup>;
begin
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(0, Length(LGroups));
end;

procedure TTestGroupConsecutiveChunks.CombineTrue_SingleChunk_SingleGroup;
var
	LGroups: TArray<TChunkGroup>;
begin
	FChunks.Add(MakeChunk(grUser, 'A', 7));
	LGroups := GroupConsecutiveChunks(FChunks, True);
	Assert.AreEqual<Integer>(1, Length(LGroups));
	Assert.AreEqual<Integer>(1, Length(LGroups[0].Chunks));
	Assert.AreEqual<Integer>(7, LGroups[0].TotalTokenCount);
end;

initialization
	TDUnitX.RegisterTestFixture(TTestGetChunkGroupKind);
	TDUnitX.RegisterTestFixture(TTestGroupConsecutiveChunks);

end.
