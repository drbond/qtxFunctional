unit functional.lazy;

// ---------------------------------------------------------------------------
//  qtxFunctional - TLazy / TLazyValue
//
//  A deferred value (a "thunk"), in the spirit of Haskell's call-by-need:
//
//    * nothing is computed until .Value is first read;
//    * with Memoise = True (the default) the result is cached, so the
//      computation runs at most once (call-by-need);
//    * with Memoise = False it is recomputed on every read (call-by-name) -
//      useful for values that depend on changing outside state;
//    * Map / Bind build NEW lazies without forcing the original.
//
//  TLazyValue is the roadmap's name for the same type.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions;

type
  TLazy = class;

  TLazyBinder = function (Value: Variant): TLazy;

  TLazy = class
  private
    FThunk:       TVarThunk;
    FValue:       Variant;
    FEvaluated:   Boolean;
    FMemoise:     Boolean;
    FEvaluations: Integer;
    function GetValue: Variant;
  public
    constructor Create(const Thunk: TVarThunk; Memoise: Boolean = True);

    // An already-evaluated lazy (Haskell's "pure" / "return")
    class function Pure(const Value: Variant): TLazy;

    // Functor: apply Fn to the eventual value, still lazily
    function Map(const Fn: TVarFunc): TLazy;

    // Monad: chain a computation that itself produces a lazy
    function Bind(const Fn: TLazyBinder): TLazy;

    property Value: Variant read GetValue;
    property IsEvaluated: Boolean read FEvaluated;  // has a cached value
    property Memoised: Boolean read FMemoise;
    property EvaluationCount: Integer read FEvaluations;
  end;

  TLazyValue = TLazy;

implementation

constructor TLazy.Create(const Thunk: TVarThunk; Memoise: Boolean = True);
begin
  FThunk := Thunk;
  FMemoise := Memoise;
  FEvaluated := False;
  FEvaluations := 0;
end;

class function TLazy.Pure(const Value: Variant): TLazy;
var
  Fixed: Variant;
begin
  Fixed := Value;
  Result := TLazy.Create(
    function: Variant
    begin
      Result := Fixed;
    end);
  Result.GetValue;   // force immediately - it is free
end;

function TLazy.GetValue: Variant;
begin
  if not FMemoise then
  begin
    Inc(FEvaluations);
    exit(FThunk());
  end;

  if not FEvaluated then
  begin
    Inc(FEvaluations);
    FValue := FThunk();
    FEvaluated := True;
    FThunk := nil;   // release the closure (and anything it captured)
  end;
  Result := FValue;
end;

function TLazy.Map(const Fn: TVarFunc): TLazy;
var
  Source: TLazy;
  Mapper: TVarFunc;
begin
  Source := Self;
  Mapper := Fn;
  Result := TLazy.Create(
    function: Variant
    begin
      Result := Mapper(Source.Value);
    end, FMemoise);
end;

function TLazy.Bind(const Fn: TLazyBinder): TLazy;
var
  Source: TLazy;
  Binder: TLazyBinder;
begin
  Source := Self;
  Binder := Fn;
  Result := TLazy.Create(
    function: Variant
    begin
      Result := Binder(Source.Value).Value;
    end, FMemoise);
end;

end.
