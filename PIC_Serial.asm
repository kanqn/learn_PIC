;**************************************************************
;  Test Program for RS232C Library
;  Connect This PIC Test Module to Personal computer.
;  If receive data from PC then display that data to LCD.
;  If Switch is ON then send one data to PC.
;  http://www.picfun.com/serial21.html
;************************************************************** 
        LIST        P=PIC16F84A
        INCLUDE     "P16F84A.INC"
;****************　テスト用サンプル　*******************
;***** for LCD variables ****
DPDT    EQU 14H     ;buffer for display data
CNT1    EQU 15H     ;Timer counter
CNT3    EQU     16H
CNT4    EQU 17H
;
;
;*************************************
;  Jump vector
;*************************************
        ORG     0       ;reset
        GOTO        START
        ORG     4       ;Interrupt
        GOTO        INT232

        ORG     08H     ;code

;*****************************************************************
;  シリアル通信ライブラリserial communication routine via RS232C.
;  　本プログラムはRS232Cインターフェースを介するシリアル通信
;　　を実現するプログラム群から構成されている。
;  　仕様は下記This Baud Rate is presettable by changing a one parameter.
;  　　・半二重通信、最大速度9600bps
;  　　・スタートビットは１ビット固定
;　　　・ストップビット長は標準１ビット（EXTRAで任意ビット数指定可)
;　　　・データ長は８ビット固定
;  　　・時間はタイマー０で作成し割込みを使用している
;　　　・RS、CSの信号は制御していない。
;  本プログラムは下記モジュール群から構成されている。
;    1.１バイト送信プロセス(PUTCHRA)
;　　　　TXREGのデータを指定通信速度で出力する
;    2.１バイト受信プロセス(GETCHAR)
;　　　　受信したデータをRXREGにセットする。受信完了でRECVがOn
;    3.割込み処理(INT232)
;    4.データ定義、初期化処理（OPEN232)
;
;  初期化部分では通信で使うポートを下記で指定している。
;    1.PORTA RA4 は受信ポート(RXD）
;    2.PORTA RA3 は送信ポート(TXD）
;
;  本ライブラリでは受信データの有無は「RECV」フラグを監視
;　することで行い、１の場合には受信データ有りとなる。
;
;  パラメータは通信速度を決めるBAUDRATEのみで下記となっている。
;　下記通信速度はクロックが１０MHｚの時である。
;    BAUDRATE
;　　  5=300bps  3=1200bps  2=2400bps  1=4800bps  0=9600bps
;
;  通信結果のステータスは"RESULT"フラグの各ビットで知る。
;     BIT0 : TXBUSY  (1の時送信中)
;     BIT1 : unused
;     BIT2 : RXBUSY  (1の時受信中)
;     BIT3 : RECV    (1の時受信データ有り)
;     BIT4 : ERROR   (1の時エラー発生)
;*****************************************************************
;*************************************
;  データの定義プロセス
;*************************************
#DEFINE     TXBUSY      RESULT,0    ;送信中ビジー
#DEFINE     RXBUSY      RESULT,2    ;受信中ビジー
#DEFINE     RECV        RESULT,3    ;受信完了
#DEFINE     ERROR       RESULT,4    ;受信エラーフラグ

;****  Define Variables  ***** 
RESULT      EQU     0CH     ;送受信ステータス
WREG        EQU     0DH     ;wreg save area
SREG        EQU     0EH     ;status reg save area
BITCNT      EQU     0FH     ;ビットカウンタ
EXTRA       EQU     10H     ;ストップビット長
TXREG       EQU     11H     ;送信データバッファ
RXREG       EQU     12H     ;受信データバッファ
CNT2        EQU     13H     ;スキュー用遅延
BITTMR1     SET     06AH        ;スキップ用ビット幅

;********  通信速度の設定とパラメータ設定 ****
; 通信速度はタイマ0の割込み周期と割込みの回数カウンタで決まる。
; 通信速度 パルス幅 Tcy数 prescaler BITTMR　BAUDRATE
;   300    3333.33  8333    64    　130(7E)  　5
;  1200    833.33　 2083    16    　130(7E)  　3
;  2400    416.67   1041     8  　　128(80)  　2
;  4800    208.33    521     4    　124(84)  　1
;  9600    104.17    260     2    　122(86)  　0
;
;　BAUDRATEを通信速度指定のパラメータとし下記数値で指定する。
;　　（クロックが１０MHｚの場合）
;　　 5=300bps  3=1200bps  2=2400bps  1=4800bps  0=9600bps
;
;　下記は9600bpsの場合の例
;
BAUDRATE    SET 0   ;プリスケーラ値
BITTMR      SET 086H    ;TMR0 DATA 134
;
;**********************************************************
;***************** RS232C通信ライブラリ部　***************
;*************************************
;  初期化プロセス
;*************************************

OPEN232
        CLRF        RESULT      ;ステータスのクリア
                BSF             STATUS,RP0      ;Set page 1
        BCF     TRISA,3     ;Set TXD
        BSF     TRISA,4     ;Set RXD
                BCF             STATUS,RP0      ;Set Page 0
                BSF     PORTA,3     ;TXD SET TO H
        RETURN

;************************************
; １バイト送信プロセス
;　送信データをTXREGにセット後CALLする
;************************************
PUTCHAR
        BSF     TXBUSY      ;送信中ビジーセット
        MOVLW       8       ;ビットカウンタ初期値
        MOVWF       BITCNT      ;初期値セット
        MOVLW       1       ;ストップビット長=1
        MOVWF       EXTRA       ;ストップビット長セット
        CALL        TXSTART     ;スタートビット送信開始
        BCF     INTCON,T0IF ;割込みフラグリセット
        BSF     INTCON,T0IE ;タイマ0割込み許可
        RETURN
;**** スタートビット送信処理 ****
TXSTART
        CLRF        TMR0        ;タイマ初期セット
        BSF     STATUS,RP0  ;page 1
        CLRWDT
        MOVLW       BAUDRATE    ;set prescaler
        MOVWF       OPTION_REG
        BCF     STATUS,RP0  ;page 0 
        BCF     PORTA,3     ;スタートビット出力
        MOVLW       BITTMR      ;ビット幅タイマセット
        MOVWF       TMR0        ;start timer
        RETURN

;*************************************
;  １バイト受信プロセス
;*************************************
GETCHAR
        BCF     RECV        ;受信完了フラグクリア
        MOVLW       9       ;ビットカウンタ初期値
        MOVWF       BITCNT      ;初期値セット
        CLRF        RXREG       ;バッファクリア
        BCF     ERROR       ;エラーフラグクリア
;****  スタートビット受信待ち  ****
        CLRF        TMR0        ;タイマリセット
        BSF     STATUS,RP0  ;page 1
        CLRWDT              ;clear WDT
        MOVLW       038H        ;set to external WDT
        MOVWF       OPTION_REG
        BCF     STATUS,RP0  ;page 0
        MOVLW       0FFH        ;フルカウント値セット
        MOVWF       TMR0        ;
        BCF     INTCON,T0IF ;タイマ0割込みフラグリセット
        BSF     INTCON,T0IE ;タイマ0割込み許可
        RETURN              ;割込み待ち

;****************************************
; Interrupt process module
;****************************************
INT232
        BTFSS       INTCON,T0IF ;TMR0's interrupt?
        RETFIE              ;not, quick return
        BCF     INTCON,T0IF ;reset T0IF bit
;****  save W register & status register
        MOVWF       WREG        ;save w reg
        SWAPF       STATUS,W    ;status to wreg
        MOVWF       SREG        ;save status
        BTFSC       TXBUSY      ;送信中か？
        GOTO        TXNEXT      ;送信割込み処理へ
        BTFSC       RXBUSY      ;受信中か？
        GOTO        RXNEXT      ;受信割込み処理へ
        GOTO        STARTBIT    ;スタートビット受信処理へ
;****  register restore and return
RESTORE     
        SWAPF       SREG,W      ;get saved status
        MOVWF       STATUS
        SWAPF       WREG,F      ;get saved wreg
        SWAPF       WREG,W
        RETFIE

;***************************************
;  送信割込み処理プロセス
;***************************************
TXNEXT
        MOVLW       BITTMR      ;タイマ０再スタート
        MOVWF       TMR0
        MOVF        BITCNT,W    ;ビットカウンタ減算
        BTFSC       STATUS,Z    ;ビット終了か
        GOTO        STOPBIT     ;ストップビット送信へ
NEXTTXBIT
        DECF        BITCNT,F    ;ビットカウンタ減算
        BSF     STATUS,C    ;C on
        RRF     TXREG,F     ;送信データシフト
        BTFSS       STATUS,C    ;０か１か
        BCF     PORTA,3     ;0 out
        BTFSC       STATUS,C
        BSF     PORTA,3     ;1 out
        GOTO        RESTORE     ;return         
;****  ストップビット送信プロセス  ****
STOPBIT
        MOVF        EXTRA,W     ;ストップビット送信中か
        BTFSC       STATUS,Z    ;end test
        GOTO        DONE        ;全ビット送信完了
        DECF        EXTRA,F     ;ストップビット長減算
        BSF     PORTA,3     ;ストップビット出力
        GOTO        RESTORE     ;戻る
;***  all end of send ****
DONE
        BCF     INTCON,T0IE ;タイマ０割込み禁止
        BCF     TXBUSY      ;送信ビジーフラグクリア
        GOTO        RESTORE     ;戻る


;*****************************************
;　スタートビット受信割込み処理プロセス
;*****************************************
STARTBIT
        CLRWDT              ;WDTリセット
        CALL        TIME10      ;10usec遅延
        BTFSC       PORTA,4     ;再度スタートビット確認
        GOTO        NOISE       ;エラーリターン
        BSF     RXBUSY      ;受信中ビジーセット
;
        CLRF        TMR0        ;タイマ初期化
        BSF     STATUS,RP0  ;page 1
        MOVLW       BAUDRATE    ;ビット幅セット
        MOVWF       OPTION_REG
        BCF     STATUS,RP0  ;page 0
        MOVLW       BITTMR1     ;ビット幅の1.1倍をセットし
        MOVWF       TMR0        ;スタートビットをスキップ
        GOTO        RESTORE     ;戻る
;*** スタートビットエラー（何もしない） ****
NOISE       
        MOVLW       0FFH        ;再度スタートビット受信待ち
        MOVWF       TMR0
        GOTO        RESTORE     ;戻る

;*****************************************
;　受信割込み処理プロセス
;*****************************************
RXNEXT
        BSF     STATUS,RP0  ;page 1
        CLRWDT              ;タイマ初期化
        MOVLW       BAUDRATE
        MOVWF       OPTION_REG
        BCF     STATUS,RP0  ;page 0
        MOVLW       BITTMR
        MOVWF       TMR0        ;再スタート
        DECFSZ      BITCNT,F    ;ビットカウント終了か？
        GOTO        NEXTRXBIT
;*** ストップビット受信処理  ***
        BTFSS       PORTA,4     ;ストップビットの確認
        BSF     ERROR       ;エラーフラグON
        BCF     INTCON,T0IE ;割込み禁止
        BCF     RXBUSY      ;受信中ビジーフラグクリア
        BSF     RECV        ;受信データ有りフラグセット
        GOTO        RESTORE

;**** 残りのビット受信処理  ***
NEXTRXBIT
        BCF     STATUS,C    ;ビット０セット
        BTFSC       PORTA,4     ;受信ビット０か１か
        BSF     STATUS,C    ;1 の時１にセット
        RRF     RXREG,F     ;RXREGに１ビット書き込み
        GOTO        RESTORE     ;戻る
;*****  10usec 遅延タイマ
TIME10                      ;10usec
        MOVLW       7H      
        MOVWF       CNT2        
T_LP2       DECFSZ      CNT2,F      ;2+3*7-1=22     
        GOTO        T_LP2       
        RETURN              ;22+1=23

;******************  This is the end of RS232C modules *********************
;**************************************************************************




;**************　テスト用サンプル部サブルーチン　********************
;*************************************
;  メインプログラムのサンプル
;*************************************

START
        BCF     INTCON,GIE  ;Interrupt disable
        CALL        PORT_INI    ;Initialise
        CALL        LCD_INI     ;Reset LCD
        CALL        LCD_CLR     ;clear display
;       CALL        OPEN232     ;RS232通信初期化
        BSF     INTCON,GIE  ;permit interrupt

;****  Event check loop
EVENT
        BTFSS       PORTB,1     ;SW1
        GOTO        SW1
        BTFSS       PORTB,2     ;SW2
        GOTO        SW2
        BTFSS       PORTB,3     ;SW3
        GOTO        SW3
        GOTO        EVENT       ;loop

;****  Event process  *****                     
SW1
        MOVLW       "1"     ;SEND 1
        MOVWF       TXREG
        CALL        PUTCHAR     ;send data
        GOTO        WAITLP
SW2
        MOVLW       "2"
        MOVWF       TXREG
        CALL        PUTCHAR
        GOTO        WAITLP
SW3
        MOVLW       "3"
        MOVWF       TXREG
        CALL        PUTCHAR
WAITLP
        BTFSC       TXBUSY      ;wait end of sending
        GOTO        WAITLP
;****   Received data process
        CALL        GETCHAR     ;start receive
RCVWAIT     BTFSS       RECV        ;wait received
        GOTO        RCVWAIT
        BTFSC       ERROR       ;error check
        GOTO        ERR
        MOVF        RXREG,W     ;get received data
        CALL        LCD_DATA    ;display to LCD
        GOTO        EVENT
;***  receive error display ****
ERR     MOVLW       "?"
        CALL        LCD_DATA    ;display ?
        GOTO        EVENT

;******************************************************
;  PORT A & B Initialize Routine
;  This routine includes RS232C and LCD initilization.
;******************************************************

PORT_INI
                BSF             STATUS,RP0      ;Set page 1
        MOVLW       0FH     ;only RB0,1,2,3 input
                MOVWF           TRISB           ;PortB set all output
                MOVLW           010H            ;only RA4 input
                MOVWF           TRISA           ;PortA set
                BCF             STATUS,RP0      ;Set Page 0
                BSF     PORTA,3     ;RS232 TX SET TO H
                RETURN          



;***************************************************
;   液晶表示器制御サブルーチン群
;***************************************************

;****  LCD Data Write  ****
LCD_DATA
        MOVWF       DPDT        ;save dat
        ANDLW       0F0H        ;mask lower
        MOVWF       PORTB
        BCF     PORTA,1     ;R/W
        BSF     PORTA,2     ;RS high
        BSF     PORTA,0     ;E high
        BCF     PORTA,0     ;E low
        SWAPF       DPDT,W      ;get data lower
        ANDLW       0F0H
        MOVWF       PORTB
        BSF     PORTA,0
        BCF     PORTA,0
        CALL        LCD_BUSY
        RETURN

;****  LCD command out  *****
LCD_CMD
        MOVWF       DPDT        ;save dat
        ANDLW       0F0H        ;mask lower
        MOVWF       PORTB
        BCF     PORTA,1     ;R/W
        BCF     PORTA,2     ;RS low
        BSF     PORTA,0     ;E high
        BCF     PORTA,0     ;E low
        SWAPF       DPDT,W      ;get data lower
        ANDLW       0F0H
        MOVWF       PORTB
        BSF     PORTA,0
        BCF     PORTA,0
        CALL        LCD_BUSY
        RETURN

;****  LCD Display Clear ****
LCD_CLR
        MOVLW       01H     ;clear command
        CALL        LCD_CMD
        RETURN

;****  Initialize  *****
LCD_INI
        CALL        TIME5M      ;wait
        MOVLW       030H        ;Function set 8bits
        MOVWF       PORTB
        BCF     PORTA,1     ;R/W
        BCF     PORTA,2     ;RS
        BSF     PORTA,0     ;E high
        BCF     PORTA,0     ;E low
        CALL        TIME5M      ;wait
        MOVLW       030H        ;Function reset 8bits 
        MOVWF       PORTB
        BCF     PORTA,1     ;R/W
        BCF     PORTA,2     ;RS
        BSF     PORTA,0     ;E high
        BCF     PORTA,0     ;E low
        CALL        TIME100
        MOVLW       030H        ;Function reset 8bits
        MOVWF       PORTB
        BCF     PORTA,1
        BCF     PORTA,2
        BSF     PORTA,0
        BCF     PORTA,0
        CALL        TIME100
        MOVLW       020H        ;Function set 4bits mode
        MOVWF       PORTB       ;under the 8bits mode
        BCF     PORTA,1
        BCF     PORTA,2
        BSF     PORTA,0
        BCF     PORTA,0
        CALL        TIME100     ;From here 4bits mode

        MOVLW       02CH        ;function DL=0 4bit mode
        CALL        LCD_CMD
        MOVLW       08H     ;Display off D=C=B=0
        CALL        LCD_CMD
        MOVLW       0CH     ;Display on D=1 C=B=0
        CALL        LCD_CMD
        MOVLW       06H     ;Entry I/D=1 S=0
        CALL        LCD_CMD
        RETURN


;****  LCD Busy Check  ************
LCD_BUSY
        CLRF        DPDT
        BSF     STATUS,RP0  ;Bank 1
        BSF     OPTION_REG,7    ;Turn on PORTB pull up
        MOVLW       0FEH        ;PORTB input
        MOVWF       TRISB
        BCF     STATUS,RP0  ;Bank 0
        BCF     PORTA,2     ;RS low
        BSF     PORTA,1     ;R/W high
        BSF     PORTA,0     ;E high
        MOVF        PORTB,W     ;get upper
        BCF     PORTA,0     ;E low
        ANDLW       0F0H        ;Mask out lower
        MOVWF       DPDT
        BSF     PORTA,0     ;E high
        MOVF        PORTB,W     ;get lower
        BCF     PORTA,0     ;E low
        ANDLW       0FH     ;Mask out upper
        IORWF       DPDT,F      ;upper+lower
        BTFSC       DPDT,7      ;BUSY flag check
        GOTO        LCD_BUSY    ;retry

        BCF     PORTA,1     ;R/W low
        BSF     STATUS,RP0  ;Bank 1
        MOVLW       0EH     ;RB1,2,3 input
        MOVWF       TRISB       ;PORTB
        BCF     STATUS,RP0  ;Bank 0
        RETURN

;*********************************
;  Timer Routine
;   TIME10  :10usec
;   TIME100 :100usec
;   TIME1M  :1msec
;   TIME5M  :5msec
;*********************************

TIME100                     ;100usec
        MOVLW       9H      
        MOVWF       CNT1        
T_LP1       CALL        TIME10      ;2+(25+3)*9-1=253       
        DECFSZ      CNT1,F
        GOTO        T_LP1
        RETURN              ;254*0.4=100usec(about)

TIME1M                      ;1msec(about)
        MOVLW       0AH
        MOVWF       CNT3
T_LP3       CALL        TIME100     ;2+(254+3)*10-1=2541
        DECFSZ      CNT3,F
        GOTO        T_LP3
        RETURN              ;2542

TIME5M                      ;5msec(about)
        MOVLW       3BH
        MOVWF       CNT4
T_LP4       CALL        TIME100     ;2+(254+3)*59-1=15164
        DECFSZ      CNT4,F
        GOTO        T_LP4
        RETURN              ;15165

        END
