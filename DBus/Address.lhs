% Copyright (C) 2009 John Millikin <jmillikin@gmail.com>
% 
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

\ignore{
\begin{code}
module DBus.Address
	( Address
	, addressMethod
	, addressParameters
	, strAddress
	, parseAddresses
	) where

import Data.Char (ord, chr)
import qualified Data.Map as M
import Data.List (intercalate)
import Text.Printf (printf)
import qualified Text.Parsec as P
import Text.Parsec ((<|>))
import DBus.Util (hexToInt, eitherToMaybe)
\end{code}
}

\clearpage
\section{Addresses}

\subsection{Address syntax}

A bus address is in the format {\tt $method$:$key$=$value$,$key$=$value$...}
where the method may be empty and parameters are optional. An address's
parameter list, if present, may end with a comma. Addresses in environment
variables are separated by semicolons, and the full address list may end
in a semicolon. Multiple parameters may have the same key; in this case,
only the first parameter for each key will be stored.

The bytes allowed in each component of the address are given by the following
chart, where each character is understood to be its ASCII value:

\begin{table}[h]
\begin{center}
\begin{tabular}{ll}
\toprule
Component   & Allowed Characters \\
\midrule
Method      & Any except {\tt `;'} and {\tt `:'} \\
Param key   & Any except {\tt `;'}, {\tt `,'}, and {\tt `='} \\
Param value & {\tt `0'} to {\tt `9'} \\
            & {\tt `a'} to {\tt `z'} \\
            & {\tt `A'} to {\tt `Z'} \\
            & Any of: {\tt - \textunderscore{} / \textbackslash{} * . \%} \\
\bottomrule
\end{tabular}
\end{center}
\end{table}

In parameter values, any byte may be encoded by prepending the \% character
to its value in hexadecimal. \% is not allowed to appear unless it is
followed by two hexadecimal digits. Every other allowed byte is termed
an ``optionally encoded'' byte, and may appear unescaped in parameter
values.

\begin{code}
optionallyEncoded :: String
optionallyEncoded = ['0'..'9'] ++ ['a'..'z'] ++ ['A'..'Z'] ++ "-_/\\*."
\end{code}

The address simply stores its method and parameter map, with a custom
{\tt Show} instance to provide easier debugging.

\begin{code}
data Address = Address
	{ addressMethod     :: String
	, addressParameters :: M.Map String String
	} deriving (Eq)

instance Show Address where
	showsPrec d x = showParen (d> 10) $
		showString' ["Address \"", strAddress x, "\""] where
		showString' = foldr (.) id . map showString
\end{code}

Parsing is straightforward; the input string is divided into addresses by
semicolons, then further by colons and commas. Parsing will fail if any
of the addresses in the input failed to parse.

\begin{code}
parseAddresses :: String -> Maybe [Address]
parseAddresses s = eitherToMaybe $ P.parse parser "" s where
	address = do
		method <- P.many (P.noneOf ":;")
		P.char ':'
		params <- P.sepEndBy param (P.char ',')
		return $ Address method (M.fromList params)
	
	param = do
		key <- P.many1 (P.noneOf "=;,")
		P.char '='
		value <- P.many1 (encodedValue <|> unencodedValue)
		return (key, value)
	
	parser = do
		as <- P.sepEndBy1 address (P.char ';')
		P.eof
		return as
	
	unencodedValue = P.oneOf optionallyEncoded
	encodedValue = do
		P.char '%'
		hex <- P.count 2 P.hexDigit
		return . chr . hexToInt $ hex
\end{code}

Converting an {\tt Address} back to a {\tt String} is just the reverse
operation. Note that because the original parameter order is not preserved,
the string produced might differ from the original input.

\begin{code}
strAddress :: Address -> String
strAddress (Address t ps) = t ++ ":" ++ ps' where
	ps' = intercalate "," $ do
		(k, v) <- M.toList ps
		[k ++ "=" ++ (v >>= encode)]
	encode c | elem c optionallyEncoded = [c]
	         | otherwise       = printf "%%%02X" (ord c)
\end{code}
