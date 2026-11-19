# DMA in streaming per l'acceleratore Sobel: revisione e correzioni

## 1. Contesto

Nella versione precedente, i pixel arrivavano dalla UART del SoC e la CPU li copiava uno a uno in una BRAM di ingresso. A quel punto l'acceleratore elaborava l'immagine e scriveva il risultato in una BRAM di uscita, da cui la CPU rileggeva i dati per rimandarli indietro.

La nuova versione elimina la CPU dal percorso dei dati e anche le due BRAM:

```
UART RX ─► packer (4 byte → 1 word) ─► pixel_acc ─► unpacker (1 word → 4 byte) ─► UART TX
```

La CPU programma soltanto la lunghezza del frame e la velocità della linea seriale, dà lo START e aspetta il DONE (o l'interrupt). Per supportare questo flusso è stata modificata anche la FSM interna dell'acceleratore: ora avanza quando arriva una word, invece di leggere da una memoria.

## 2. Stato iniziale

L'architettura generale era corretta e già implementata in tutte le sue parti:

- **ricevitore UART** con campionamento a metà bit;
- **packer** che raggruppa 4 byte in una word da 32 bit;
- **acceleratore** con la FSM adattata allo streaming;
- **unpacker con trasmettitore UART**, preceduto da un piccolo buffer da una word sull'uscita;
- **registri APB** per configurazione, avvio e stato.

L'idea di fondo era che, entrando e uscendo una word per volta alla stessa velocità, il buffer da una word bastasse ad assorbire le piccole differenze di tempo.

### FSM dell'acceleratore

Nel funzionamento normale la FSM nuova era **corretta**. Abbiamo ricostruito passo per passo come la cache viene riempita e fatta scorrere, e i dati finiscono nelle posizioni giuste esattamente come nella versione con BRAM. È corretta anche la scelta di caricare il dato nello stesso ciclo in cui arriva, dato che non c'è più la latenza di un ciclo della memoria.

## 3. Problemi trovati

### 3.1 L'uscita non produce una word per ogni word in ingresso

L'ipotesi "entra una word, esce una word" vale solo a metà riga. In realtà l'acceleratore emette i risultati in modo irregolare:

| Fase del frame | Ingressi | Uscite |
|---|---|---|
| Prima riga | 88 word | nessuna (servono due righe per calcolare la prima) |
| Righe intermedie, word 0–1 | 2 word | nessuna |
| Righe intermedie, word 2–86 | 1 word | 1 word |
| Righe intermedie, word 87 | 1 word | **3 word in 3 cicli consecutivi** |
| Ultima riga | nessuno | **88 word in 88 cicli consecutivi** |

Un buffer da una word non può reggere queste raffiche:

- **a fine riga** la terza word sovrascriveva la seconda, quindi si perdeva almeno una word per ogni riga;
- **sull'ultima riga** se ne perdevano circa 86, perché la UART impiega circa 40 tempi di bit per trasmettere una word, mentre l'acceleratore ne produce una per ciclo di clock.

### 3.2 Il trasmettitore era più lento del ricevitore

Ogni byte trasmesso durava qualche ciclo di clock in più dei 10 tempi di bit teorici, a causa dei passaggi di controllo tra un byte e l'altro. Il ricevitore invece riceve un byte esattamente ogni 10 tempi di bit. Il ritardo si accumulava per tutto il frame: in simulazione veloce circa il 15% in più per ogni word, quindi nessun buffer di dimensione fissa sarebbe bastato.

Inoltre i bit trasmessi non avevano tutti la stessa durata: il primo durava un ciclo in più, l'ultimo un ciclo in meno. A velocità reale l'effetto è trascurabile. In simulazione veloce, con 2 cicli per bit, il campionamento cadeva proprio sul fronte del segnale.

### 3.3 Avvio e sequenza di controllo

- **La prima word poteva andare persa.** L'acceleratore partiva anche all'arrivo della prima word, ma il comando di avvio arrivava un ciclo dopo il dato. Quella word trovava quindi l'acceleratore ancora fermo.
- **Byte ricevuti senza START.** Il packer raggruppava byte anche quando il DMA non era stato avviato. Uno START dato a metà di una word sfasava tutti i byte successivi.
- **Il contatore di word in ingresso non serviva a niente.** Veniva aggiornato, ma non fermava la ricezione a fine frame.

### 3.4 Stato e interrupt

- **Il DONE non si poteva cancellare,** e quindi nemmeno l'interrupt, che restava sempre attivo.
- **Il DONE si alzava troppo presto,** a fine calcolo e non quando l'ultimo byte era uscito dalla UART.
- **Il secondo frame partiva male.** All'avvio di un secondo frame lo stato "occupato" veniva subito azzerato.

### 3.5 FSM: problemi secondari

- **Non era riavviabile:** i contatori di riga e colonna non venivano azzerati allo START, quindi un secondo frame partiva da una posizione sbagliata.
- **Nessun segnale per le word scartate:** se una word arrivava mentre la FSM non poteva accettarla, veniva scartata senza nessuna segnalazione.
- **Mancava il controllo di flusso in uscita:** la FSM non aveva modo di sapere se l'uscita era pronta a ricevere.

### 3.6 Perché i test non lo mostravano

Il testbench del sistema completo leggeva i risultati direttamente dall'uscita dell'acceleratore, **non dalla linea seriale**. Le word perse nel DMA di uscita quindi non comparivano mai. Il testbench del solo sottosistema usava ancora i vecchi registri delle BRAM, che non esistono più.

## 4. Modifiche effettuate

### 4.1 FSM dell'acceleratore

La logica di base è rimasta invariata. Sono stati aggiunti tre meccanismi:

- **Azzeramento allo START:** i contatori di posizione ripartono da zero a ogni frame, così l'acceleratore si può riavviare.
- **Controllo di flusso in uscita (`out_ready`):** nei passi che non dipendono da un ingresso, cioè la fine di ogni riga e tutta l'ultima riga, la FSM avanza solo se l'uscita può accettare il dato. L'ultima riga viene così emessa al ritmo della UART invece che in un'unica raffica.
- **Segnale di accettazione in ingresso (`in_ready`):** indica quando la FSM può prendere una word. Il DMA lo usa per segnalare eventuali word perse.

### 4.2 Uscita: FIFO al posto del buffer singolo

Il buffer da una word è stato sostituito da una piccola FIFO da 8 word, realizzata con registri e quindi ancora senza BRAM. Con il trasmettitore alla stessa velocità del ricevitore, l'arretrato massimo è di circa 3 word, che si raggiungono nella raffica di fine riga. L'ultima riga è regolata dal controllo di flusso, quindi 8 posizioni lasciano ampio margine.

### 4.3 Trasmettitore UART riscritto

- **Durata dei bit uniforme:** ogni bit dura esattamente il numero di cicli configurato.
- **Nessun ciclo vuoto tra un byte e l'altro:** il byte successivo parte nello stesso istante in cui termina il bit di stop del precedente.
- **Stessa velocità del ricevitore:** il trasmettitore produce un byte ogni 10 tempi di bit, esattamente come il ricevitore li riceve, quindi l'arretrato non cresce più.

### 4.4 Ingresso e avvio

- **Packer attivo solo nel frame:** il packer accetta byte solo dopo lo START e finché il frame non è completo. I byte arrivati prima o dopo vengono ignorati, senza sfasare il raggruppamento.
- **Avvio solo da START:** l'acceleratore viene avviato soltanto dallo START, un ciclo dopo l'abilitazione del DMA. La prima word arriva comunque molto più tardi, perché servono almeno 40 tempi di bit, e trova l'acceleratore già pronto.

### 4.5 Registri di stato e interrupt

- **Un solo stato occupato/terminato:** al posto dei due insiemi di flag che si sovrapponevano.
- **DONE a fine trasmissione:** si alza quando l'ultimo byte del frame è uscito dalla UART, quindi quando il risultato è davvero arrivato a destinazione.
- **DONE cancellabile:** si azzera scrivendo 1 sul suo bit, e con lui l'interrupt.
- **Due flag d'errore**, che si azzerano a ogni START:
  - **RX_OVERRUN:** una word in ingresso è stata persa;
  - **TX_OVERFLOW:** una word in uscita è stata persa.

### 4.6 Firmware

Il firmware aspetta solo il DONE del DMA, lo cancella e può leggere i flag d'errore.

### 4.7 Testbench

- **Testbench del sottosistema:** riscritto per lo streaming, senza CPU, quindi veloce da simulare. Invia un'immagine sulla linea seriale e riceve il risultato dalla linea seriale. Poi verifica che:
  - il risultato coincida con un filtro Sobel di riferimento calcolato nel testbench;
  - coincida anche con quanto prodotto dall'acceleratore, cioè che nessuna word sia stata persa nel DMA;
  - i flag d'errore restino a zero;
  - l'interrupt si cancelli correttamente;
  - un secondo frame consecutivo funzioni.
- **Testbench del sistema completo:** ora legge anche la linea seriale, aspetta il DONE reale e invia l'immagine solo dopo che il firmware ha dato lo START.

## 5. Verifica

Simulazioni del sottosistema in Questa, con trasmissione seriale continua senza pause:

| Test | Esito |
|---|---|
| Immagine `kaleidoscope`, 1 frame | PASS: output seriale = Sobel di riferimento = output dell'acceleratore |
| Immagine `pattern`, 2 frame consecutivi | PASS su entrambi i frame, quindi il riavvio funziona |
| Verifica indipendente con `sim/check_sobel.py` | PASS su entrambe le immagini |
| Flag di errore | sempre a zero |

Il caso testato è il più sfavorevole: chi invia trasmette alla stessa velocità del nostro trasmettitore, senza pause. Il DMA chiude il frame circa 73 µs dopo l'ultimo byte ricevuto, cioè il tempo necessario a trasmettere l'ultima riga.

## 6. Punti aperti

- **Simulazione del sistema completo con CPU:** non è ancora stata eseguita, perché richiede di ricompilare il firmware.
- **FPGA:**
  - Il collegamento della UART del DMA ai pin della scheda usa riferimenti gerarchici, che in genere Vivado non sintetizza. Le porte vanno portate fino al livello superiore attraverso i moduli intermedi.
  - Sulla scheda il clock è di circa 15 MHz, non 100 MHz. Il numero di cicli per bit va ricalcolato come frequenza / baud rate (circa 65 per 230400 baud) e va verificato l'eventuale divisore di clock del sottosistema.
- **Testbench unitari della FSM e del contatore di indirizzi e file di forme d'onda:** erano già superati prima di queste modifiche e andrebbero aggiornati.
