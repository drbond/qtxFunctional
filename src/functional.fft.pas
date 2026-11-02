unit functional.fft;

// ---------------------------------------------------------------------------
//  qtxFunctional - functional Fourier transforms  (Stage 6)
//
//  TComplex is a value record, so complex numbers are immutable by nature.
//
//  FFT is the recursive Cooley-Tukey algorithm written as pure functions:
//  split into even and odd halves (Tabulate), transform each half
//  recursively, then combine with twiddle factors (Tabulate again).
//  No array is ever modified after it is built.
//
//      X[k]         = E[k] + w^k * O[k]
//      X[k + n/2]   = E[k] - w^k * O[k]        w = exp(-2*pi*i/n)
//
//  InverseFFT uses the conjugation identity  ifft(x) = conj(fft(conj(x)))/n.
//  DFT is the direct O(n^2) definition, used to cross-check the FFT.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.floats;

type
  TComplex = record
    Re: Float;
    Im: Float;
  end;

  TComplexArray     = array of TComplex;
  TComplexIndexFunc = function (Index: Integer): TComplex;

  TComplexOps = class
  public
    class function Make(Re, Im: Float): TComplex;
    class function Add(const A, B: TComplex): TComplex;
    class function Sub(const A, B: TComplex): TComplex;
    class function Mul(const A, B: TComplex): TComplex;
    class function Scale(const A: TComplex; K: Float): TComplex;
    class function Conj(const A: TComplex): TComplex;
    class function Polar(Theta: Float): TComplex;     // exp(i*theta)
    class function Magnitude(const A: TComplex): Float;
  end;

  TFourier = class
  public
    class function Tabulate(Size: Integer; const Fn: TComplexIndexFunc): TComplexArray;
    class function FromReals(const Values: TFloatArray): TComplexArray;
    class function IsPowerOfTwo(N: Integer): Boolean;

    class function FFT(const X: TComplexArray): TComplexArray;
    class function InverseFFT(const X: TComplexArray): TComplexArray;
    class function DFT(const X: TComplexArray): TComplexArray;

    class function Magnitudes(const X: TComplexArray): TFloatArray;
    class function RealParts(const X: TComplexArray): TFloatArray;
    class function MaxDifference(const A, B: TComplexArray): Float;
  end;

implementation

{ TComplexOps }

class function TComplexOps.Make(Re, Im: Float): TComplex;
begin
  Result.Re := Re;
  Result.Im := Im;
end;

class function TComplexOps.Add(const A, B: TComplex): TComplex;
begin
  Result := Make(A.Re + B.Re, A.Im + B.Im);
end;

class function TComplexOps.Sub(const A, B: TComplex): TComplex;
begin
  Result := Make(A.Re - B.Re, A.Im - B.Im);
end;

class function TComplexOps.Mul(const A, B: TComplex): TComplex;
begin
  Result := Make(A.Re * B.Re - A.Im * B.Im, A.Re * B.Im + A.Im * B.Re);
end;

class function TComplexOps.Scale(const A: TComplex; K: Float): TComplex;
begin
  Result := Make(A.Re * K, A.Im * K);
end;

class function TComplexOps.Conj(const A: TComplex): TComplex;
begin
  Result := Make(A.Re, -A.Im);
end;

class function TComplexOps.Polar(Theta: Float): TComplex;
begin
  Result := Make(Cos(Theta), Sin(Theta));
end;

class function TComplexOps.Magnitude(const A: TComplex): Float;
begin
  Result := Sqrt(A.Re * A.Re + A.Im * A.Im);
end;

{ TFourier }

class function TFourier.Tabulate(Size: Integer; const Fn: TComplexIndexFunc): TComplexArray;
var
  i: Integer;
begin
  for i := 0 to Size - 1 do
    Result.Add(Fn(i));
end;

class function TFourier.FromReals(const Values: TFloatArray): TComplexArray;
var
  Data: TFloatArray;
  i: Integer;
begin
  for i := 0 to High(Values) do
    Data.Add(Values[i]);
  Result := Tabulate(Length(Data),
    function (Index: Integer): TComplex
    begin
      Result := TComplexOps.Make(Data[Index], 0);
    end);
end;

class function TFourier.IsPowerOfTwo(N: Integer): Boolean;
begin
  if N < 1 then
    exit(False);
  while (N mod 2) = 0 do
    N := N div 2;
  Result := N = 1;
end;

class function TFourier.FFT(const X: TComplexArray): TComplexArray;
var
  Input, Evens, Odds, E, O: TComplexArray;
  N, Half: Integer;
begin
  N := Length(X);
  if not IsPowerOfTwo(N) then
    raise EFunctional.Create('TFourier.FFT: length must be a power of two');
  Input := X;

  if N = 1 then
    exit(Tabulate(1,
      function (Index: Integer): TComplex
      begin
        Result := Input[0];
      end));

  Half := N div 2;
  Evens := Tabulate(Half,
    function (Index: Integer): TComplex
    begin
      Result := Input[2 * Index];
    end);
  Odds := Tabulate(Half,
    function (Index: Integer): TComplex
    begin
      Result := Input[2 * Index + 1];
    end);

  E := FFT(Evens);
  O := FFT(Odds);

  Result := Tabulate(N,
    function (K: Integer): TComplex
    var
      M: Integer;
      Twiddled: TComplex;
    begin
      M := K mod Half;
      Twiddled := TComplexOps.Mul(TComplexOps.Polar(-2 * Pi * M / N), O[M]);
      if K < Half then
        Result := TComplexOps.Add(E[M], Twiddled)
      else
        Result := TComplexOps.Sub(E[M], Twiddled);
    end);
end;

class function TFourier.InverseFFT(const X: TComplexArray): TComplexArray;
var
  Input, Transformed: TComplexArray;
  N: Integer;
begin
  Input := X;
  N := Length(X);
  Transformed := FFT(Tabulate(N,
    function (Index: Integer): TComplex
    begin
      Result := TComplexOps.Conj(Input[Index]);
    end));
  Result := Tabulate(N,
    function (Index: Integer): TComplex
    begin
      Result := TComplexOps.Scale(TComplexOps.Conj(Transformed[Index]), 1 / N);
    end);
end;

class function TFourier.DFT(const X: TComplexArray): TComplexArray;
var
  Input: TComplexArray;
  N: Integer;
begin
  Input := X;
  N := Length(X);
  Result := Tabulate(N,
    function (K: Integer): TComplex
    var
      T: Integer;
    begin
      Result := TComplexOps.Make(0, 0);
      for T := 0 to N - 1 do
        Result := TComplexOps.Add(Result,
          TComplexOps.Mul(Input[T], TComplexOps.Polar(-2 * Pi * K * T / N)));
    end);
end;

class function TFourier.Magnitudes(const X: TComplexArray): TFloatArray;
var
  i: Integer;
begin
  for i := 0 to High(X) do
    Result.Add(TComplexOps.Magnitude(X[i]));
end;

class function TFourier.RealParts(const X: TComplexArray): TFloatArray;
var
  i: Integer;
begin
  for i := 0 to High(X) do
    Result.Add(X[i].Re);
end;

class function TFourier.MaxDifference(const A, B: TComplexArray): Float;
var
  i: Integer;
  D: Float;
begin
  Result := 0;
  for i := 0 to High(A) do
  begin
    D := TComplexOps.Magnitude(TComplexOps.Sub(A[i], B[i]));
    if D > Result then
      Result := D;
  end;
end;

end.
