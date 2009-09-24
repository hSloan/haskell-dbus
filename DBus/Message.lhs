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
module DBus.Message (
	 Message (..)
	,MethodCall (..)
	,MethodReturn (..)
	,Error (..)
	,Signal (..)
	,Flag (..)
	,HeaderField (..)
	) where
import Data.Bits ((.|.), (.&.))
import Data.Word (Word8)
import Data.Maybe (fromJust)

import qualified DBus.Types as T
\end{code}
}

\clearpage
\section{Messages}

A message represents a single message, with a header and body. Some parts
of the header, such as the serial, endianness, and body length, are not
included in the message --- instead, they are generated when a message is
marshalled.

\begin{code}
class Message a where
	messageTypeCode     :: a -> Word8
	messageHeaderFields :: a -> [HeaderField]
	messageFlags        :: a -> [Flag]
	messageBody         :: a -> [T.Variant]
\end{code}

\subsection{Flags}

Flags are represented as the integral value of each flag OR'd into a single
byte.

\begin{code}
data Flag = NoReplyExpected
          | NoAutoStart
	deriving (Show, Eq)
\end{code}

\begin{code}
encodeFlags :: [Flag] -> Word8
encodeFlags flags = foldr (.|.) 0 $ map flagValue flags where
	flagValue NoReplyExpected = 0x1
	flagValue NoAutoStart     = 0x2
\end{code}

\begin{code}
decodeFlags :: Word8 -> [Flag]
decodeFlags flagsByte = flags where
	flagSet = [(0x1, NoReplyExpected), (0x2, NoAutoStart)]
	flags = flagSet >>= \(x, y) -> [y | flagsByte .&. x > 0]
\end{code}

\subsection{Header fields}

\begin{code}
data HeaderField = Path        T.ObjectPath
                 | Interface   T.InterfaceName
                 | Member      T.MemberName
                 | ErrorName   T.ErrorName
                 | ReplySerial T.Serial
                 | Destination T.BusName
                 | Sender      T.BusName
                 | Signature   T.Signature
	deriving (Show, Eq)
\end{code}

\begin{code}
header' :: T.Variable a => Word8 -> a -> T.Variant
header' code x = T.toVariant $ T.Structure
	[ T.toVariant code
	, T.toVariant $ T.toVariant x
	]

unheader :: T.Variant -> Maybe (Word8, T.Variant)
unheader v = do
	struct <- T.fromVariant v
	(c, v) <- case struct of
		T.Structure [x, y] -> return  (x, y)
		_                  -> Nothing
	c' <- T.fromVariant c
	v' <- T.fromVariant v
	return (c', v')

instance T.Variable HeaderField where
	defaultSignature _ = fromJust . T.mkSignature $ "(yv)"
	
	toVariant (Path x)        = header' 1 x
	toVariant (Interface x)   = header' 2 x
	toVariant (Member x)      = header' 3 x
	toVariant (ErrorName x)   = header' 4 x
	toVariant (ReplySerial x) = header' 5 x
	toVariant (Destination x) = header' 6 x
	toVariant (Sender x)      = header' 7 x
	toVariant (Signature x)   = header' 8 x
	
	fromVariant v = unheader v >>= \v' -> case v' of
		(1, x) -> fmap Path        $ T.fromVariant x
		(2, x) -> fmap Interface   $ T.fromVariant x
		(3, x) -> fmap Member      $ T.fromVariant x
		(4, x) -> fmap ErrorName   $ T.fromVariant x
		(5, x) -> fmap ReplySerial $ T.fromVariant x
		(6, x) -> fmap Destination $ T.fromVariant x
		(7, x) -> fmap Sender      $ T.fromVariant x
		(8, x) -> fmap Signature   $ T.fromVariant x
		_      -> Nothing
\end{code}

\subsection{Message types}

\subsubsection{Method calls}

\begin{code}
data MethodCall = MethodCall {
	 methodCallPath        :: T.ObjectPath
	,methodCallMember      :: T.MemberName
	,methodCallInterface   :: Maybe T.InterfaceName
	,methodCallDestination :: Maybe T.BusName
	,methodCallFlags       :: [Flag]
	,methodCallBody        :: [T.Variant]
	}
	deriving (Show, Eq)

instance Message MethodCall where
	messageTypeCode _ = 1
	messageFlags      = methodCallFlags
	messageBody       = methodCallBody
	messageHeaderFields m = concat
		[ [ Path    $ methodCallPath m
		  ,  Member $ methodCallMember m
		  ]
		, maybe' Interface . methodCallInterface $ m
		, maybe' Destination . methodCallDestination $ m
		]
\end{code}

\subsubsection{Method returns}

\begin{code}
data MethodReturn = MethodReturn {
	 methodReturnSerial      :: T.Serial
	,methodReturnDestination :: Maybe T.BusName
	,methodReturnFlags       :: [Flag]
	,methodReturnBody        :: [T.Variant]
	}
	deriving (Show, Eq)

instance Message MethodReturn where
	messageTypeCode _ = 2
	messageFlags      = methodReturnFlags
	messageBody       = methodReturnBody
	messageHeaderFields m = concat
		[ [ ReplySerial $ methodReturnSerial m
		  ]
		, maybe' Destination . methodReturnDestination $ m
		]
\end{code}

\subsubsection{Errors}

\begin{code}
data Error = Error {
	 errorName        :: T.ErrorName
	,errorSerial      :: T.Serial
	,errorDestination :: Maybe T.BusName
	,errorFlags       :: [Flag]
	,errorBody        :: [T.Variant]
	}
	deriving (Show, Eq)

instance Message Error where
	messageTypeCode _ = 3
	messageFlags      = errorFlags
	messageBody       = errorBody
	messageHeaderFields m = concat
		[ [ ErrorName   $ errorName m
		  , ReplySerial $ errorSerial m
		  ]
		, maybe' Destination . errorDestination $ m
		]
\end{code}

\subsubsection{Signals}

\begin{code}
data Signal = Signal {
	 signalPath      :: T.ObjectPath
	,signalMember    :: T.MemberName
	,signalInterface :: T.InterfaceName
	,signalFlags     :: [Flag]
	,signalBody      :: [T.Variant]
	}
	deriving (Show, Eq)

instance Message Signal where
	messageTypeCode _ = 4
	messageFlags      = signalFlags
	messageBody       = signalBody
	messageHeaderFields m =
		[ Path      $ signalPath m
		, Member    $ signalMember m
		, Interface $ signalInterface m
		]
\end{code}

\begin{code}
maybe' :: (a -> b) -> Maybe a -> [b]
maybe' f x = maybe [] (\x' -> [f x']) x
\end{code}
