/// <summary>
///   Unit tests for TGeminiChunk: GetFullText, GetThinkingText, TryGetResource.
/// </summary>
unit Tests.GeminiFile.Chunk;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model;

type
  [TestFixture]
  TTestGeminiChunk = class
  public
    [Test]
    procedure GetFullText_WithoutParts_ReturnsText;
    [Test]
    procedure GetFullText_WithParts_ConcatenatesNonThoughtText;
    [Test]
    procedure GetFullText_WithParts_SkipsThoughtParts;
    [Test]
    procedure GetThinkingText_WithoutParts_ReturnsTextIfIsThought;
    [Test]
    procedure GetThinkingText_WithoutParts_ReturnsEmptyIfNotThought;
    [Test]
    procedure GetThinkingText_WithParts_ConcatenatesThoughtPartsOnly;
    [Test]
    procedure TryGetResource_TrueWithInlineImage;
    [Test]
    procedure TryGetResource_TrueWithPartsInlineData;
    [Test]
    procedure TryGetResource_FalseWhenNoResources;
    [Test]
    procedure TryGetResource_PrefersInlineImageOverParts;
    [Test]
    procedure TryGetResource_FallsBackToPartsInlineData;
  end;

implementation

{ TTestGeminiChunk }

procedure TTestGeminiChunk.GetFullText_WithoutParts_ReturnsText;
var
  LChunk: TGeminiChunk;
begin
  LChunk := TGeminiChunk.Create;
  try
    LChunk.Text := 'Hello world';
    Assert.AreEqual('Hello world', LChunk.GetFullText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.GetFullText_WithParts_ConcatenatesNonThoughtText;
var
  LChunk: TGeminiChunk;
  LPart1, LPart2: TGeminiPart;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart1 := TGeminiPart.Create;
    LPart1.Text := 'Part one. ';
    LPart1.IsThought := False;
    LChunk.Parts.Add(LPart1);

    LPart2 := TGeminiPart.Create;
    LPart2.Text := 'Part two.';
    LPart2.IsThought := False;
    LChunk.Parts.Add(LPart2);

    Assert.AreEqual('Part one. Part two.', LChunk.GetFullText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.GetFullText_WithParts_SkipsThoughtParts;
var
  LChunk: TGeminiChunk;
  LPart1, LPart2, LPart3: TGeminiPart;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart1 := TGeminiPart.Create;
    LPart1.Text := 'Visible. ';
    LPart1.IsThought := False;
    LChunk.Parts.Add(LPart1);

    LPart2 := TGeminiPart.Create;
    LPart2.Text := 'Thinking...';
    LPart2.IsThought := True;
    LChunk.Parts.Add(LPart2);

    LPart3 := TGeminiPart.Create;
    LPart3.Text := 'More visible.';
    LPart3.IsThought := False;
    LChunk.Parts.Add(LPart3);

    Assert.AreEqual('Visible. More visible.', LChunk.GetFullText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.GetThinkingText_WithoutParts_ReturnsTextIfIsThought;
var
  LChunk: TGeminiChunk;
begin
  LChunk := TGeminiChunk.Create;
  try
    LChunk.Text := 'Thinking about it...';
    LChunk.IsThought := True;
    Assert.AreEqual('Thinking about it...', LChunk.GetThinkingText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.GetThinkingText_WithoutParts_ReturnsEmptyIfNotThought;
var
  LChunk: TGeminiChunk;
begin
  LChunk := TGeminiChunk.Create;
  try
    LChunk.Text := 'Regular text';
    LChunk.IsThought := False;
    Assert.AreEqual('', LChunk.GetThinkingText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.GetThinkingText_WithParts_ConcatenatesThoughtPartsOnly;
var
  LChunk: TGeminiChunk;
  LPart1, LPart2, LPart3: TGeminiPart;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart1 := TGeminiPart.Create;
    LPart1.Text := 'Regular text';
    LPart1.IsThought := False;
    LChunk.Parts.Add(LPart1);

    LPart2 := TGeminiPart.Create;
    LPart2.Text := 'Thought one. ';
    LPart2.IsThought := True;
    LChunk.Parts.Add(LPart2);

    LPart3 := TGeminiPart.Create;
    LPart3.Text := 'Thought two.';
    LPart3.IsThought := True;
    LChunk.Parts.Add(LPart3);

    Assert.AreEqual('Thought one. Thought two.', LChunk.GetThinkingText);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.TryGetResource_TrueWithInlineImage;
var
  LChunk: TGeminiChunk;
  LRes: TGeminiResource;
begin
  LChunk := TGeminiChunk.Create;
  try
    LChunk.InlineImage := TGeminiResource.Create('image/jpeg', 'AAAA', 0);
    Assert.IsTrue(LChunk.TryGetResource(LRes));
    Assert.AreEqual('image/jpeg', LRes.MimeType);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.TryGetResource_TrueWithPartsInlineData;
var
  LChunk: TGeminiChunk;
  LPart: TGeminiPart;
  LRes: TGeminiResource;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart := TGeminiPart.Create;
    LPart.InlineData := TGeminiResource.Create('image/png', 'BBBB', 0);
    LChunk.Parts.Add(LPart);
    Assert.IsTrue(LChunk.TryGetResource(LRes));
    Assert.AreEqual('image/png', LRes.MimeType);
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.TryGetResource_FalseWhenNoResources;
var
  LChunk: TGeminiChunk;
  LPart: TGeminiPart;
  LRes: TGeminiResource;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart := TGeminiPart.Create;
    LPart.Text := 'Just text';
    LChunk.Parts.Add(LPart);
    Assert.IsFalse(LChunk.TryGetResource(LRes));
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.TryGetResource_PrefersInlineImageOverParts;
var
  LChunk: TGeminiChunk;
  LPart: TGeminiPart;
  LRes: TGeminiResource;
begin
  LChunk := TGeminiChunk.Create;
  try
    LChunk.InlineImage := TGeminiResource.Create('image/jpeg', 'AAAA', 0);
    LPart := TGeminiPart.Create;
    LPart.InlineData := TGeminiResource.Create('image/png', 'BBBB', 0);
    LChunk.Parts.Add(LPart);

    Assert.IsTrue(LChunk.TryGetResource(LRes));
    Assert.AreEqual('image/jpeg', LRes.MimeType, 'Should prefer InlineImage over part InlineData');
  finally
    LChunk.Free;
  end;
end;

procedure TTestGeminiChunk.TryGetResource_FallsBackToPartsInlineData;
var
  LChunk: TGeminiChunk;
  LPart: TGeminiPart;
  LRes: TGeminiResource;
begin
  LChunk := TGeminiChunk.Create;
  try
    LPart := TGeminiPart.Create;
    LPart.InlineData := TGeminiResource.Create('image/png', 'BBBB', 0);
    LChunk.Parts.Add(LPart);

    Assert.IsTrue(LChunk.TryGetResource(LRes));
    Assert.AreEqual('image/png', LRes.MimeType);
  finally
    LChunk.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiChunk);

end.
