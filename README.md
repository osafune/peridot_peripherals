PERIDOTペリフェラル
===================

PERIDOTの標準ペリフェラル集です。


対象となるツール
----------------

- Qsys 16.1以降
- MAX10、CycloneIV、CycloneVを搭載し、UARTまたはFT245/FT240X/FT232Hが接続されたボード


使い方
------

- ip以下のフォルダをcloneして、プロジェクトのローカルに保存するか、保存場所にライブラリパスを通します。
- Qsysでコンポーンネントをaddして適宜操作します。

ペリフェラルのレジスタについてはdoc以下のpdfを参照してください。


ペリフェラルの概要
==================

PERIDOT Host Bridge
-------------------

ホストからQsys内部へアクセスするブリッジを提供します。  
[Canarium](https://github.com/kimushu/canarium)パッケージを利用することで、クライアント側のJavaScriptからQsys内部のAvalon-MMスレーブペリフェラル、およびNiosIIのHALと相互にアクセスすることができます。  
また、NiosIIとクライアントとの排他制御、通知、ブートシーケンス制御の機能を提供します。  
MAX10ではデュアルコンフィグレーションスキームを利用したリコンフィグレーション機能を提供します。  


SDRAM
-----

PERIDOTボードで使用しているSDRAMのパラメータセットです。


ライセンス
=========

[The MIT License (MIT)](https://opensource.org/licenses/MIT)  
詳細は[license.txt](https://raw.githubusercontent.com/osafune/peridot_newgen/master/license.txt)を参照ください。  

Copyright (c) 2017 J-7SYSTEM WORKS LIMITED.
