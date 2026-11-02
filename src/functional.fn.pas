unit functional.fn;

// ---------------------------------------------------------------------------
//  qtxFunctional - TFn and TValueFunction
//
//  TFn is a reusable function *object*: it wraps a TVarFunc together with a
//  readable name, so composed functions can describe themselves. Composition
//  follows the mathematical convention:
//
//      TFn.Compose(F, G)  represents  F(G(x))      name "F . G"
//
//  TValueFunction provides functions over record-like values (JavaScript
//  objects held in a Variant) and class instances, so pipelines are not
//  limited to numbers and strings. Record "updates" never mutate: they
//  return a modified copy.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions;

type
  TFn = class;
  TFnArray = array of TFn;
  TStringArray = array of String;

  TFn = class
  private
    FFunc: TVarFunc;
    FName: String;
  public
    constructor Create(const Name: String; const Func: TVarFunc);

    class function Identity: TFn;
    class function Compose(const F, G: TFn): TFn;       // F(G(x))
    class function Pipeline(const Steps: TFnArray): TFn; // left to right

    function After(const G: TFn): TFn;                   // Self(G(x))
    function AndThen(const G: TFn): TFn;                 // G(Self(x))

    function Apply(const Value: Variant): Variant;
    function Iterate(const Value: Variant; Times: Integer): Variant; // f(f(..f(x)))

    property Func: TVarFunc read FFunc;
    property Name: String read FName;
  end;

  TValueFunction = class
  public
    // Build a record-like value: MakeRecord(['x','y'], [1, 2])
    class function MakeRecord(const Names: TStringArray; const Values: TVarArray): Variant;

    // Read one field of a record-like value
    class function Field(const Name: String): TVarFunc;

    // Immutable update: copy of the record with Name replaced by Fn(old value)
    class function UpdateField(const Name: String; const Fn: TVarFunc): TVarFunc;

    // Predicate on one field: Where('age', Adult)
    class function Where(const Name: String; const Predicate: TVarPredicate): TVarPredicate;

    // Class instances travel through Variant pipelines via these
    class function FromObject(const Instance: TObject): Variant;
    class function ToObject(const Value: Variant): TObject;
  end;

implementation

{ TFn }

constructor TFn.Create(const Name: String; const Func: TVarFunc);
begin
  FName := Name;
  FFunc := Func;
end;

class function TFn.Identity: TFn;
begin
  Result := TFn.Create('id', TVarFunction.Identity());
end;

class function TFn.Compose(const F, G: TFn): TFn;
begin
  Result := TFn.Create(F.Name + ' . ' + G.Name,
    TVarFunction.Compose(F.Func, G.Func));
end;

class function TFn.Pipeline(const Steps: TFnArray): TFn;
var
  i: Integer;
begin
  Result := TFn.Identity;
  for i := 0 to High(Steps) do
    if i = 0 then
      Result := Steps[0]
    else
      Result := Result.AndThen(Steps[i]);
end;

function TFn.After(const G: TFn): TFn;
begin
  Result := TFn.Compose(Self, G);
end;

function TFn.AndThen(const G: TFn): TFn;
begin
  Result := TFn.Compose(G, Self);
end;

function TFn.Apply(const Value: Variant): Variant;
begin
  Result := FFunc(Value);
end;

function TFn.Iterate(const Value: Variant; Times: Integer): Variant;
var
  i: Integer;
begin
  Result := Value;
  for i := 1 to Times do
    Result := FFunc(Result);
end;

{ TValueFunction }

class function TValueFunction.MakeRecord(const Names: TStringArray;
  const Values: TVarArray): Variant;
var
  i: Integer;
begin
  Result := TVariant.CreateObject;
  for i := 0 to High(Names) do
    TVariant.PropertyWrite(Result, Names[i], Values[i]);
end;

class function TValueFunction.Field(const Name: String): TVarFunc;
var
  Key: String;
begin
  Key := Name;
  Result := function (Value: Variant): Variant
    begin
      Result := TVariant.PropertyRead(Value, Key);
    end;
end;

class function TValueFunction.UpdateField(const Name: String;
  const Fn: TVarFunc): TVarFunc;
var
  Key: String;
  Change: TVarFunc;
begin
  Key := Name;
  Change := Fn;
  Result := function (Value: Variant): Variant
    var
      Copy: Variant;
    begin
      // Shallow copy of every field - the original is never touched
      Copy := TVariant.CreateObject;
      for var FieldName in TVariant.GetKeys(Value) do
        TVariant.PropertyWrite(Copy, FieldName, TVariant.PropertyRead(Value, FieldName));
      TVariant.PropertyWrite(Copy, Key, Change(TVariant.PropertyRead(Value, Key)));
      Result := Copy;
    end;
end;

class function TValueFunction.Where(const Name: String;
  const Predicate: TVarPredicate): TVarPredicate;
var
  Key: String;
  Test: TVarPredicate;
begin
  Key := Name;
  Test := Predicate;
  Result := function (Value: Variant): Boolean
    begin
      Result := Test(TVariant.PropertyRead(Value, Key));
    end;
end;

class function TValueFunction.FromObject(const Instance: TObject): Variant;
begin
  Result := TVariant.FromObject(Instance);
end;

class function TValueFunction.ToObject(const Value: Variant): TObject;
begin
  Result := TVariant.ToObject(Value);
end;

end.
