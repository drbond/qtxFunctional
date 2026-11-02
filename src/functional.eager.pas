unit functional.eager;

// ---------------------------------------------------------------------------
//  qtxFunctional - TEagerInteger
//
//  The conventional, *eager* baseline for comparison with TLazyInteger.
//  Every operation runs immediately over the whole collection and
//  materialises a brand new array - exactly what lazy, fused pipelines
//  avoid. Each step is recorded in TFunctionalStats.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.stats;

type
  TEagerInteger = class
  private
    FItems: TIntArray;
    class function Wrap(const Items: TIntArray): TEagerInteger;
  public
    constructor Create(const Items: TIntArray);

    class function Range(First, Last: Integer): TEagerInteger;

    function Map(const Fn: TIntFunc): TEagerInteger;
    function Filter(const Predicate: TIntPredicate): TEagerInteger;
    function Take(Count: Integer): TEagerInteger;
    function Fold(Seed: Integer; const Fn: TIntFoldFunc): Integer;

    function ToArray: TIntArray;
    function AsString: String;
    function Count: Integer;
  end;

implementation

constructor TEagerInteger.Create(const Items: TIntArray);
begin
  FItems := Items;
  Inc(TFunctionalStats.PipelineObjects);
end;

class function TEagerInteger.Wrap(const Items: TIntArray): TEagerInteger;
begin
  Inc(TFunctionalStats.IntermediateArrays);
  TFunctionalStats.ArrayElements := TFunctionalStats.ArrayElements + Length(Items);
  Result := TEagerInteger.Create(Items);
end;

class function TEagerInteger.Range(First, Last: Integer): TEagerInteger;
var
  Items: TIntArray;
  i: Integer;
begin
  for i := First to Last do
    Items.Add(i);
  TFunctionalStats.SourceElements := TFunctionalStats.SourceElements + Length(Items);
  Result := Wrap(Items);
end;

function TEagerInteger.Map(const Fn: TIntFunc): TEagerInteger;
var
  Items: TIntArray;
  i: Integer;
begin
  for i := 0 to High(FItems) do
    Items.Add(Fn(FItems[i]));
  Result := Wrap(Items);
end;

function TEagerInteger.Filter(const Predicate: TIntPredicate): TEagerInteger;
var
  Items: TIntArray;
  i: Integer;
begin
  for i := 0 to High(FItems) do
    if Predicate(FItems[i]) then
      Items.Add(FItems[i]);
  Result := Wrap(Items);
end;

function TEagerInteger.Take(Count: Integer): TEagerInteger;
var
  Items: TIntArray;
  i: Integer;
begin
  for i := 0 to High(FItems) do
  begin
    if i >= Count then
      break;
    Items.Add(FItems[i]);
  end;
  Result := Wrap(Items);
end;

function TEagerInteger.Fold(Seed: Integer; const Fn: TIntFoldFunc): Integer;
var
  i: Integer;
begin
  Result := Seed;
  for i := 0 to High(FItems) do
    Result := Fn(Result, FItems[i]);
end;

function TEagerInteger.ToArray: TIntArray;
var
  i: Integer;
begin
  for i := 0 to High(FItems) do
    Result.Add(FItems[i]);
end;

function TEagerInteger.AsString: String;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(FItems) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + IntToStr(FItems[i]);
  end;
  Result := Result + ']';
end;

function TEagerInteger.Count: Integer;
begin
  Result := Length(FItems);
end;

end.
