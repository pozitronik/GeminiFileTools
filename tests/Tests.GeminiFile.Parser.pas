/// <summary>
///   Unit tests for GeminiFile.Parser: JSON parsing, helpers, edge cases, errors.
/// </summary>
unit Tests.GeminiFile.Parser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.Generics.Collections,
  DUnitX.TestFramework,
  GeminiFile.Types,
  GeminiFile.Model,
  GeminiFile.Parser;

type
  [TestFixture]
  TTestGeminiFileParser = class
  private
    FParser: IGeminiFileParser;
    FRunSettings: TGeminiRunSettings;
    FChunks: TObjectList<TGeminiChunk>;
    function ParseJson(const AJson: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // Minimal valid JSON
    [Test]
    procedure Parse_MinimalValidJson_EmptyChunks;

    // RunSettings tests
    [Test]
    procedure Parse_RunSettings_ModelTemperatureTopPTopKMaxTokens;
    [Test]
    procedure Parse_RunSettings_SafetySettingsArray;
    [Test]
    procedure Parse_RunSettings_ResponseModalities;

    // SystemInstruction tests
    [Test]
    procedure Parse_SystemInstruction_WithText;
    [Test]
    procedure Parse_SystemInstruction_EmptyObject;

    // Chunk parsing tests
    [Test]
    procedure Parse_Chunk_UserRoleTextTokenCount;
    [Test]
    procedure Parse_Chunk_ModelRoleWithFinishReason;
    [Test]
    procedure Parse_Chunk_IsThoughtWithThinkingBudget;
    [Test]
    procedure Parse_Chunk_InlineImageCreatesResource;
    [Test]
    procedure Parse_Chunk_DriveImageExtractsId;
    [Test]
    procedure Parse_Chunk_ErrorMessageAndSafetyRatings;
    [Test]
    procedure Parse_Chunk_PartsWithTextAndThought;
    [Test]
    procedure Parse_Chunk_PartsWithInlineData;

    // Error handling tests
    [Test]
    procedure Parse_MalformedJson_RaisesError;
    [Test]
    procedure Parse_NonObjectRoot_RaisesError;

    // JSON helper tests
    [Test]
    procedure JsonHelpers_NullHandling;
    [Test]
    procedure JsonHelpers_MissingKeys;
    [Test]
    procedure JsonHelpers_TypeMismatches;
  end;

implementation

{ TTestGeminiFileParser }

procedure TTestGeminiFileParser.Setup;
begin
  FParser := TGeminiFileParser.Create;
  FRunSettings := TGeminiRunSettings.Create;
  FChunks := TObjectList<TGeminiChunk>.Create(True);
end;

procedure TTestGeminiFileParser.TearDown;
begin
  FChunks.Free;
  FRunSettings.Free;
  FParser := nil;
end;

function TTestGeminiFileParser.ParseJson(const AJson: string): string;
var
  LStream: TStringStream;
begin
  LStream := TStringStream.Create(AJson, TEncoding.UTF8);
  try
    Result := FParser.Parse(LStream, FRunSettings, FChunks);
  finally
    LStream.Free;
  end;
end;

procedure TTestGeminiFileParser.Parse_MinimalValidJson_EmptyChunks;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[]}}');
  Assert.AreEqual<Integer>(0, FChunks.Count);
end;

procedure TTestGeminiFileParser.Parse_RunSettings_ModelTemperatureTopPTopKMaxTokens;
begin
  ParseJson('{"runSettings":{"model":"models/gemini-2.5-pro",' +
    '"temperature":0.7,"topP":0.95,"topK":40,"maxOutputTokens":8192},' +
    '"chunkedPrompt":{"chunks":[]}}');

  Assert.AreEqual('models/gemini-2.5-pro', FRunSettings.Model);
  Assert.AreEqual(Double(0.7), FRunSettings.Temperature, 0.001);
  Assert.AreEqual(Double(0.95), FRunSettings.TopP, 0.001);
  Assert.AreEqual<Integer>(40, FRunSettings.TopK);
  Assert.AreEqual<Integer>(8192, FRunSettings.MaxOutputTokens);
end;

procedure TTestGeminiFileParser.Parse_RunSettings_SafetySettingsArray;
begin
  ParseJson('{"runSettings":{"safetySettings":[' +
    '{"category":"HARM_CATEGORY_HARASSMENT","threshold":"BLOCK_NONE"},' +
    '{"category":"HARM_CATEGORY_HATE_SPEECH","threshold":"BLOCK_LOW_AND_ABOVE"}]},' +
    '"chunkedPrompt":{"chunks":[]}}');

  Assert.AreEqual<Integer>(2, Length(FRunSettings.SafetySettings));
  Assert.AreEqual('HARM_CATEGORY_HARASSMENT', FRunSettings.SafetySettings[0].Category);
  Assert.AreEqual('BLOCK_NONE', FRunSettings.SafetySettings[0].Threshold);
  Assert.AreEqual('HARM_CATEGORY_HATE_SPEECH', FRunSettings.SafetySettings[1].Category);
end;

procedure TTestGeminiFileParser.Parse_RunSettings_ResponseModalities;
begin
  ParseJson('{"runSettings":{"responseModalities":["IMAGE","TEXT"]},' +
    '"chunkedPrompt":{"chunks":[]}}');

  Assert.AreEqual<Integer>(2, Length(FRunSettings.ResponseModalities));
  Assert.AreEqual('IMAGE', FRunSettings.ResponseModalities[0]);
  Assert.AreEqual('TEXT', FRunSettings.ResponseModalities[1]);
end;

procedure TTestGeminiFileParser.Parse_SystemInstruction_WithText;
var
  LSysInstr: string;
begin
  LSysInstr := ParseJson('{"systemInstruction":{"text":"You are a helpful assistant."},' +
    '"chunkedPrompt":{"chunks":[]}}');

  Assert.AreEqual('You are a helpful assistant.', LSysInstr);
end;

procedure TTestGeminiFileParser.Parse_SystemInstruction_EmptyObject;
var
  LSysInstr: string;
begin
  LSysInstr := ParseJson('{"systemInstruction":{},' +
    '"chunkedPrompt":{"chunks":[]}}');

  Assert.AreEqual('', LSysInstr);
end;

procedure TTestGeminiFileParser.Parse_Chunk_UserRoleTextTokenCount;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"text":"Hello","role":"user","tokenCount":5}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.AreEqual('Hello', FChunks[0].Text);
  Assert.IsTrue(FChunks[0].Role = grUser, 'Role should be grUser');
  Assert.AreEqual<Integer>(5, FChunks[0].TokenCount);
end;

procedure TTestGeminiFileParser.Parse_Chunk_ModelRoleWithFinishReason;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"text":"Response","role":"model","finishReason":"STOP"}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.IsTrue(FChunks[0].Role = grModel, 'Role should be grModel');
  Assert.AreEqual('STOP', FChunks[0].FinishReason);
end;

procedure TTestGeminiFileParser.Parse_Chunk_IsThoughtWithThinkingBudget;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"text":"Thinking...","role":"model","isThought":true,"thinkingBudget":1024}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.IsTrue(FChunks[0].IsThought);
  Assert.AreEqual<Integer>(1024, FChunks[0].ThinkingBudget);
end;

procedure TTestGeminiFileParser.Parse_Chunk_InlineImageCreatesResource;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"role":"model","inlineImage":{"mimeType":"image/jpeg","data":"SGVsbG8="}}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.IsNotNull(FChunks[0].InlineImage);
  Assert.AreEqual('image/jpeg', FChunks[0].InlineImage.MimeType);
end;

procedure TTestGeminiFileParser.Parse_Chunk_DriveImageExtractsId;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"role":"user","driveImage":{"id":"abc123"}}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.AreEqual('abc123', FChunks[0].DriveImageId);
end;

procedure TTestGeminiFileParser.Parse_Chunk_ErrorMessageAndSafetyRatings;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"role":"model","errorMessage":"Content blocked",' +
    '"safetyRatings":[{"category":"HARM_CATEGORY_HARASSMENT","probability":"HIGH"}]}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.AreEqual('Content blocked', FChunks[0].ErrorMessage);
  Assert.AreEqual<Integer>(1, Length(FChunks[0].SafetyRatings));
  Assert.AreEqual('HARM_CATEGORY_HARASSMENT', FChunks[0].SafetyRatings[0].Category);
  Assert.AreEqual('HIGH', FChunks[0].SafetyRatings[0].Probability);
end;

procedure TTestGeminiFileParser.Parse_Chunk_PartsWithTextAndThought;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"role":"model","parts":[' +
    '{"text":"Visible response","thought":false},' +
    '{"text":"Internal reasoning","thought":true}]}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.AreEqual<Integer>(2, FChunks[0].Parts.Count);
  Assert.AreEqual('Visible response', FChunks[0].Parts[0].Text);
  Assert.IsFalse(FChunks[0].Parts[0].IsThought);
  Assert.AreEqual('Internal reasoning', FChunks[0].Parts[1].Text);
  Assert.IsTrue(FChunks[0].Parts[1].IsThought);
end;

procedure TTestGeminiFileParser.Parse_Chunk_PartsWithInlineData;
begin
  ParseJson('{"chunkedPrompt":{"chunks":[' +
    '{"role":"model","parts":[' +
    '{"inlineData":{"mimeType":"image/png","data":"AAAA"}}]}]}}');

  Assert.AreEqual<Integer>(1, FChunks.Count);
  Assert.AreEqual<Integer>(1, FChunks[0].Parts.Count);
  Assert.IsNotNull(FChunks[0].Parts[0].InlineData);
  Assert.AreEqual('image/png', FChunks[0].Parts[0].InlineData.MimeType);
end;

procedure TTestGeminiFileParser.Parse_MalformedJson_RaisesError;
begin
  Assert.WillRaise(
    procedure
    begin
      ParseJson('not valid json');
    end,
    EGeminiParseError, '');
end;

procedure TTestGeminiFileParser.Parse_NonObjectRoot_RaisesError;
begin
  Assert.WillRaise(
    procedure
    begin
      ParseJson('[1, 2, 3]');
    end,
    EGeminiParseError, '');
end;

procedure TTestGeminiFileParser.JsonHelpers_NullHandling;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('nullVal', TJSONNull.Create);
    Assert.AreEqual('default', JsonStr(LObj, 'nullVal', 'default'));
    Assert.AreEqual<Integer>(42, JsonInt(LObj, 'nullVal', 42));
    Assert.IsTrue(IsNaN(JsonFloat(LObj, 'nullVal')));
    Assert.IsTrue(JsonBool(LObj, 'nullVal', True));
  finally
    LObj.Free;
  end;
end;

procedure TTestGeminiFileParser.JsonHelpers_MissingKeys;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    Assert.AreEqual('fallback', JsonStr(LObj, 'missing', 'fallback'));
    Assert.AreEqual<Integer>(99, JsonInt(LObj, 'missing', 99));
    Assert.AreEqual(Double(3.14), JsonFloat(LObj, 'missing', 3.14), 0.001);
    Assert.IsFalse(JsonBool(LObj, 'missing', False));
  finally
    LObj.Free;
  end;
end;

procedure TTestGeminiFileParser.JsonHelpers_TypeMismatches;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('strVal', 'hello');

    // Asking for int from a string value -> should return default
    Assert.AreEqual<Integer>(0, JsonInt(LObj, 'strVal', 0));
    // Asking for float from a string value -> should return default
    Assert.IsTrue(IsNaN(JsonFloat(LObj, 'strVal')));
    // Asking for bool from a string value -> should return default
    Assert.IsFalse(JsonBool(LObj, 'strVal', False));
  finally
    LObj.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGeminiFileParser);

end.
