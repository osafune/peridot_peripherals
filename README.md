PERIDOTペリフェラル
===================

PERIDOTの標準ペリフェラル集です。


対象となるツール
----------------

- QsysまたはPlatform Designer 17.1以降、およびNiosII SBT 17.0以降
- MAX10、CycloneIV、CycloneVを搭載し、UARTまたはFT245/FT240X/FT232Hが接続されたボード（PERIDOT Hostbridgeを使う場合）
- スレーブペリフェラルのみ使う場合は、NiosII等の32bitのバスアクセスが可能なAvalon-MMマスタがあるシステム

使い方
------

- ip以下のフォルダをcloneして、プロジェクトのローカルに保存するか、保存場所にライブラリパスを通します。
- Qsys/Platform Designerでコンポーンネントをaddして適宜操作します。
- NiosII SBT用のドライバ、ソフトウェアパッケージを使う場合は、必ずプロジェクトローカルのipフォルダ以下に保存してください。

ペリフェラルのレジスタについてはdoc以下のpdfを参照してください。


ペリフェラルの概要
==================

PERIDOT Host Bridge
-------------------
ホストからQsys内部へアクセスするブリッジを提供します。  
[Canarium](https://github.com/kimushu/canarium)パッケージを利用することで、クライアント側のJavaScriptからQsys内部のAvalon-MMスレーブペリフェラルへアクセスすることができます。  
MAX10ではデュアルコンフィグレーションスキームを利用したリコンフィグレーション機能を提供します。  

また、NiosIIを併用する場合はクライアント側との排他制御、通知、ブートシーケンス制御の機能を提供します。[PERIDOTソフトウェアパッケージ](https://github.com/kimushu/peridot_sw_packages)を利用することで、RPCサーバー側の機能を提供します。  


SDRAM
-----
PERIDOTボードで使用しているSDRAMのパラメータセットです。


PERIDOT PFC
-----------
PERIDOTのピンマトリックスセレクタおよび制御用のインターフェースを提供します。  


PERIDOT I2C
-----------
PERIDOT標準ペリフェラルで使用されるコンパクトなI2Cホストペリフェラルです。  


PERIDOT SPI
-----------
PERIDOT標準ペリフェラルで使用されるコンパクトなSPIホストペリフェラルです。  


PERIDOT SERVO
-------------
PERIDOT標準ペリフェラルで使用されるRCサーボ用コントローラです。  
周期20ms、パルス幅0.5～2.5msのPWM波形を256段階で出力します。また、設定値をアナログ出力するための1bitΔΣ変調出力を持ちます。  


PERIDOT SDIF
------------
SPI接続のSDカードI/FペリフェラルおよびNiosII SBT用のドライバ・ソフトウェアパッケージです。  
elfファイルを実行するブートローダーや、NiosII HAL上で動作する標準POSIX形式のファイルシステムを提供します。  


PERIDOT WSG
-----------
最大64和音の波形メモリ音源および、最大8チャネルのPCM再生を行うゲームメディアペリフェラルです。  
16bitステレオDACインターフェース、アナログオーディオ用の1bitΔΣ変調出力のほか、外部キー用の同期シリアル入力インターフェースを持ちます。  


PERIDOT GLCD
------------
CPUバス接続(8bit-i80タイプ)のグラフィックLCDモジュール用コントローラです。  
Qsysのメモリアドレス上に設定したVRAM領域からビットマップデータを自動転送し、高速な描画処理を行う事ができます。


PERIDOT LED
-----------
WorldSemiのシリアルLED(WS2812B等)を使用したLEDテープやマトリックスモジュール用のコントローラです。
最大16チャネルの同時出力を行い、最大65536個までのシリアルLEDを制御することができます。  
ピクセルデータメモリ、レイヤー合成・エフェクト、外部トリガなど電飾衣装やPOVに適した機能を持ちます。


PERIDOT Melody Chime
--------------------
メロディチャイムを再生します。
ペリフェラルレジスタに何か書き込む度にチャイムをトリガします。


ライセンス
=========

[The MIT License (MIT)](https://opensource.org/licenses/MIT)  
詳細は[license.txt](https://raw.githubusercontent.com/osafune/peridot_newgen/master/license.txt)を参照ください。  

(C) 2017-2019 J-7SYSTEM WORKS LIMITED.
