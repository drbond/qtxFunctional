unit functional.vector;

// ---------------------------------------------------------------------------
//  qtxFunctional - TVector and TMatrix  (Stage 6)
//
//  Immutable, Float-valued vectors and matrices built from higher-order
//  functions: Tabulate, Map, ZipWith, Fold. Every operation returns a new
//  value; nothing is changed in place.
//
//  Dot is a *fused* zip-fold: it walks both vectors once and allocates
//  nothing. DotUnfused (ZipWith then Fold) is kept to show the difference -
//  every vector allocation is recorded in TFunctionalStats.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.floats,
  functional.sequence,
  functional.stats;

type
  TFloatIndexFunc = function (Index: Integer): Float;
  TFloatCellFunc  = function (Row, Col: Integer): Float;
  TZipFoldFunc    = function (Accumulator, A, B: Float): Float;

  TVector = class
  private
    FData: TFloatArray;
    constructor CreateOwned(const Data: TFloatArray);
  public
    constructor Create(const Data: TFloatArray);   // takes a defensive copy

    class function Tabulate(Size: Integer; const Fn: TFloatIndexFunc): TVector;
    class function Zeros(Size: Integer): TVector;
    class function FromSequence(const Seq: TSequence): TVector;

    function Map(const Fn: TFloatFunc): TVector;
    function ZipWith(const Other: TVector; const Fn: TFloatFoldFunc): TVector;
    function Fold(Seed: Float; const Fn: TFloatFoldFunc): Float;
    function ZipFold(const Other: TVector; Seed: Float; const Fn: TZipFoldFunc): Float;

    function Add(const Other: TVector): TVector;
    function Sub(const Other: TVector): TVector;
    function Scale(Factor: Float): TVector;
    function Dot(const Other: TVector): Float;          // fused, no allocation
    function DotUnfused(const Other: TVector): Float;   // ZipWith(*).Fold(+)
    function Norm: Float;

    function Get(Index: Integer): Float;
    function Size: Integer;
    function ToArray: TFloatArray;
    function AsString(Decimals: Integer = 3): String;
  end;

  TVectorArray = array of TVector;

  TMatrix = class
  private
    FRows: Integer;
    FCols: Integer;
    FData: TFloatArray;   // row-major
    constructor CreateOwned(Rows, Cols: Integer; const Data: TFloatArray);
  public
    class function Tabulate(Rows, Cols: Integer; const Fn: TFloatCellFunc): TMatrix;
    class function Identity(Size: Integer): TMatrix;

    function Get(Row, Col: Integer): Float;
    function Row(Index: Integer): TVector;
    function Column(Index: Integer): TVector;
    function Transpose: TMatrix;
    function Map(const Fn: TFloatFunc): TMatrix;
    function Add(const Other: TMatrix): TMatrix;
    function Multiply(const Other: TMatrix): TMatrix;
    function Apply(const V: TVector): TVector;
    function AsString(Decimals: Integer = 3): String;

    property Rows: Integer read FRows;
    property Cols: Integer read FCols;
  end;

// Round to a fixed number of decimals for display (no "-0")
function FormatNum(Value: Float; Decimals: Integer): String;

implementation

function FormatNum(Value: Float; Decimals: Integer): String;
var
  Factor, Rounded: Float;
  i: Integer;
begin
  Factor := 1;
  for i := 1 to Decimals do
    Factor := Factor * 10;
  Rounded := Round(Value * Factor) / Factor;
  if Rounded = 0 then
    Rounded := 0;
  Result := FloatToStr(Rounded);
end;

{ TVector }

constructor TVector.CreateOwned(const Data: TFloatArray);
begin
  FData := Data;
  Inc(TFunctionalStats.IntermediateArrays);
  TFunctionalStats.ArrayElements := TFunctionalStats.ArrayElements + Length(Data);
end;

constructor TVector.Create(const Data: TFloatArray);
var
  Copy: TFloatArray;
  i: Integer;
begin
  for i := 0 to High(Data) do
    Copy.Add(Data[i]);
  CreateOwned(Copy);
end;

class function TVector.Tabulate(Size: Integer; const Fn: TFloatIndexFunc): TVector;
var
  Data: TFloatArray;
  i: Integer;
begin
  for i := 0 to Size - 1 do
    Data.Add(Fn(i));
  Result := TVector.CreateOwned(Data);
end;

class function TVector.Zeros(Size: Integer): TVector;
begin
  Result := Tabulate(Size,
    function (Index: Integer): Float
    begin
      Result := 0;
    end);
end;

class function TVector.FromSequence(const Seq: TSequence): TVector;
var
  Items: TVarArray;
  Data: TFloatArray;
  i: Integer;
begin
  Items := Seq.ToArray;
  for i := 0 to High(Items) do
    Data.Add(TVariant.AsFloat(Items[i]));
  Result := TVector.CreateOwned(Data);
end;

function TVector.Map(const Fn: TFloatFunc): TVector;
var
  Data: TFloatArray;
  i: Integer;
begin
  for i := 0 to High(FData) do
    Data.Add(Fn(FData[i]));
  Result := TVector.CreateOwned(Data);
end;

function TVector.ZipWith(const Other: TVector; const Fn: TFloatFoldFunc): TVector;
var
  Data: TFloatArray;
  i: Integer;
begin
  if Other.Size <> Size then
    raise EFunctional.Create('TVector.ZipWith: size mismatch');
  for i := 0 to High(FData) do
    Data.Add(Fn(FData[i], Other.FData[i]));
  Result := TVector.CreateOwned(Data);
end;

function TVector.Fold(Seed: Float; const Fn: TFloatFoldFunc): Float;
var
  i: Integer;
begin
  Result := Seed;
  for i := 0 to High(FData) do
    Result := Fn(Result, FData[i]);
end;

function TVector.ZipFold(const Other: TVector; Seed: Float;
  const Fn: TZipFoldFunc): Float;
var
  i: Integer;
begin
  if Other.Size <> Size then
    raise EFunctional.Create('TVector.ZipFold: size mismatch');
  Result := Seed;
  for i := 0 to High(FData) do
    Result := Fn(Result, FData[i], Other.FData[i]);
end;

function TVector.Add(const Other: TVector): TVector;
begin
  Result := ZipWith(Other,
    function (A, B: Float): Float
    begin
      Result := A + B;
    end);
end;

function TVector.Sub(const Other: TVector): TVector;
begin
  Result := ZipWith(Other,
    function (A, B: Float): Float
    begin
      Result := A - B;
    end);
end;

function TVector.Scale(Factor: Float): TVector;
begin
  Result := Map(TFloatFunction.Scale(Factor));
end;

function TVector.Dot(const Other: TVector): Float;
begin
  Result := ZipFold(Other, 0,
    function (Accumulator, A, B: Float): Float
    begin
      Result := Accumulator + A * B;
    end);
end;

function TVector.DotUnfused(const Other: TVector): Float;
begin
  Result := ZipWith(Other,
    function (A, B: Float): Float
    begin
      Result := A * B;
    end).Fold(0, TFloatFunction.Sum());
end;

function TVector.Norm: Float;
begin
  Result := Sqrt(Dot(Self));
end;

function TVector.Get(Index: Integer): Float;
begin
  Result := FData[Index];
end;

function TVector.Size: Integer;
begin
  Result := Length(FData);
end;

function TVector.ToArray: TFloatArray;
var
  i: Integer;
begin
  for i := 0 to High(FData) do
    Result.Add(FData[i]);
end;

function TVector.AsString(Decimals: Integer = 3): String;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(FData) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + FormatNum(FData[i], Decimals);
  end;
  Result := Result + ']';
end;

{ TMatrix }

constructor TMatrix.CreateOwned(Rows, Cols: Integer; const Data: TFloatArray);
begin
  FRows := Rows;
  FCols := Cols;
  FData := Data;
  Inc(TFunctionalStats.IntermediateArrays);
  TFunctionalStats.ArrayElements := TFunctionalStats.ArrayElements + Length(Data);
end;

class function TMatrix.Tabulate(Rows, Cols: Integer; const Fn: TFloatCellFunc): TMatrix;
var
  Data: TFloatArray;
  r, c: Integer;
begin
  for r := 0 to Rows - 1 do
    for c := 0 to Cols - 1 do
      Data.Add(Fn(r, c));
  Result := TMatrix.CreateOwned(Rows, Cols, Data);
end;

class function TMatrix.Identity(Size: Integer): TMatrix;
begin
  Result := Tabulate(Size, Size,
    function (Row, Col: Integer): Float
    begin
      if Row = Col then
        Result := 1
      else
        Result := 0;
    end);
end;

function TMatrix.Get(Row, Col: Integer): Float;
begin
  Result := FData[Row * FCols + Col];
end;

function TMatrix.Row(Index: Integer): TVector;
var
  Source: TMatrix;
  R: Integer;
begin
  Source := Self;
  R := Index;
  Result := TVector.Tabulate(FCols,
    function (Col: Integer): Float
    begin
      Result := Source.Get(R, Col);
    end);
end;

function TMatrix.Column(Index: Integer): TVector;
var
  Source: TMatrix;
  C: Integer;
begin
  Source := Self;
  C := Index;
  Result := TVector.Tabulate(FRows,
    function (Row: Integer): Float
    begin
      Result := Source.Get(Row, C);
    end);
end;

function TMatrix.Transpose: TMatrix;
var
  Source: TMatrix;
begin
  Source := Self;
  Result := Tabulate(FCols, FRows,
    function (Row, Col: Integer): Float
    begin
      Result := Source.Get(Col, Row);
    end);
end;

function TMatrix.Map(const Fn: TFloatFunc): TMatrix;
var
  Source: TMatrix;
  F: TFloatFunc;
begin
  Source := Self;
  F := Fn;
  Result := Tabulate(FRows, FCols,
    function (Row, Col: Integer): Float
    begin
      Result := F(Source.Get(Row, Col));
    end);
end;

function TMatrix.Add(const Other: TMatrix): TMatrix;
var
  A, B: TMatrix;
begin
  if (Other.Rows <> FRows) or (Other.Cols <> FCols) then
    raise EFunctional.Create('TMatrix.Add: size mismatch');
  A := Self;
  B := Other;
  Result := Tabulate(FRows, FCols,
    function (Row, Col: Integer): Float
    begin
      Result := A.Get(Row, Col) + B.Get(Row, Col);
    end);
end;

function TMatrix.Multiply(const Other: TMatrix): TMatrix;
var
  RowsA, ColsB: TVectorArray;
  BT: TMatrix;
  i: Integer;
begin
  if FCols <> Other.Rows then
    raise EFunctional.Create('TMatrix.Multiply: size mismatch');
  // Each cell is a dot product of a row of A with a column of B.
  // Rows and columns are built once as immutable vectors and shared.
  for i := 0 to FRows - 1 do
    RowsA.Add(Row(i));
  BT := Other.Transpose;
  for i := 0 to Other.Cols - 1 do
    ColsB.Add(BT.Row(i));
  Result := Tabulate(FRows, Other.Cols,
    function (Row, Col: Integer): Float
    begin
      Result := RowsA[Row].Dot(ColsB[Col]);
    end);
end;

function TMatrix.Apply(const V: TVector): TVector;
var
  Source: TMatrix;
  X: TVector;
begin
  if V.Size <> FCols then
    raise EFunctional.Create('TMatrix.Apply: size mismatch');
  Source := Self;
  X := V;
  Result := TVector.Tabulate(FRows,
    function (Row: Integer): Float
    begin
      Result := Source.Row(Row).Dot(X);
    end);
end;

function TMatrix.AsString(Decimals: Integer = 3): String;
var
  r: Integer;
begin
  Result := '';
  for r := 0 to FRows - 1 do
  begin
    if r > 0 then
      Result := Result + #10;
    Result := Result + Row(r).AsString(Decimals);
  end;
end;

end.
