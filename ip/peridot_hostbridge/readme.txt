PERDOT Hostbridge モジュール
βテスト版
2017/05/12 s.osafune@j7system.jp


■ ポート

avmclock  - Avalon-MMマスタのクロックドメインに接続します。
avmreset  - Avalon-MMマスタのリセットソースに接続します。
m1        - Avalon-MMマスタ
avsclock  - Avalon-MMスレーブのクロックドメインに接続します。
avsreset  - Avalon-MMスレーブのリセットソースに接続します。
s1        - Avalon-MMスレーブ（SWIペリフェラル）
avsirq    - s1ポート（SWIペリフェラル）の割り込み出力。
busreset  - コンフィグレーションレイヤのリセット出力。
corereset - コアモジュールのマスターリセット入力（Qsysの外から入力する）
hostuart  - ホスト通信インターフェース（Generic UART）
hostft    - ホスト通信インターフェース（FT245 Async FIFO）
swi       - SWIペリフェラルの出力信号（cpureset_request,led）
swi_conf  - SWIペリフェラルのコンフィグ選択信号（bootsel）
swi_epcs  - SWIペリフェラルのEPCS/EPCQ信号

avsclockは80MHz以下かつavmclock以下にしなけれなりません。



■ パラメータ

[Hostbridgeグループ]

・Host interface type
　　ホストとの通信インターフェースを指定します。
　　　Generic UART     - フローなしUART(RXDおよびTXDのみ)
　　　FT245 Async FIFO - FT245/FT240X/FT232Hの非同期FIFOインターフェース

・UART baudrate
　　ホスト通信インターフェースがUARTのとき、通信ビットレートを指定します。
　　駆動クロック周波数よっては選択できない値が発生することがあります。

・UART infifo depth
　　ホスト通信インターフェースがUARTのときの入力FIFOの深さを指定します。
　　UARTの通信速度よりも応答の遅いAvalon-MMスレーブが存在する場合には、
　　FIFOを深くします。


[ConfiguratonLayerグループ]

・Use reconfiguration function
　　PERIDOTコンフィグレーションレイヤでリコンフィグ機能を利用します。
　　MAX10 SA/SF/DA/DFデバイスで選択が可能です。

・Reconfiguration delay time
　　リコンフィグコマンドの受信からデバイスが再コンフィグレーションされるまでの
　　遅延時間を指定します。
　　この値は、通信の応答が処理されるのに十分な時間を指定しなければなりません。

・Instance alt_dual_boot cores
　　リコンフィグ機能を利用しない場合に、alt_dual_bootコアを内部でインスタンス
　　するかどうかを指定します。
　　MAX10のデュアルコンフィギュレーションスキームの選択時にこのオプションを
　　無効にした場合、PERIDOT Hostbridgeコンポーネントの外部でalt_dual_bootコアを
　　インスタンスする必要があります。

・Use a dual configuration by two of EPCS/EPCQ devices.
　　2つのEPCS/EPCQ(x1)デバイスを使用してデュアルブート機能を行います。
　　CycloneIV、CycloneV、Cyclone10 LPファミリで選択が可能です。
　　この機能を使うためにはFPGAの外にcso_nを入れ替える回路が必要です。
　　74LVC157を推奨。

・Use chip-UID for a board serial number
　　デバイスユニークIDをPERIDOTボードシリアルとして利用します。
　　MAX10ファミリ、CycloneV、ArriaV、StratixVファミリではデバイス単体で使用可能
　　です。
　　CycloneIV、Cyclone10 LPファミリではコンフィグレーションデバイスとの併用で
　　使用可能になります。
　　このオプションが無効の場合は、ボードシリアルは固定値が設定されます。

・PERIDOT identifier
　　PERIDOTボード識別子を設定します。
　　　Standard       - PERIDOT標準（J72A）
　　　Virtual        - コンフィグレーションレイヤをFPGA側に内蔵（J72B）
　　　NewGenerations - PERIDOT-NewGen（J72N）
　　　Generic        - Avalon-MMブリッジのみ使う汎用型（J72X）


[SoftwareInterfaceグループ]

・32 bit Class ID
　　PERIDOTのクラス識別IDを指定します。
　　このIDが同一のものについては、ソフトウェアバイナリのレベルで互換性を持つ
　　必要があります。

・cpureset key value
　　CPUリセットリクエストレジスタへ書き込む際のロックキーを16bitで指定します。
　　0x0000を指定するとロック機能は無効となります。

・cpureset initial value
　　CPUリセットリクエストレジスタの初期値を指定します。
　　　Negate - CPUリセットリクエスト解除（スタンドアロン動作）
　　　Assert - CPUリセットリクエスト有効（ホスト解除待ち）

・Use chip-UID readout registers
　　SWIのデバイスユニークIDを読み出すレジスタを利用します。
　　Use chip-UID for a board serial numberオプションが無効の場合、このチェックは
　　無効になります。

・Use EPCS/EPCQ access registers
　　SWIのEPCS/EPCQにアクセスするレジスタ（SPIマスタ機能）を利用します。
　　CycloneIV、Cyclone10 LPファミリでデバイスユニークIDを利用する場合は、この
　　チェックは常に有効になります。

・Use message and software interrput registers
　　SWIのメッセージレジスタおよびソフトウェア割り込み機能を利用します。


