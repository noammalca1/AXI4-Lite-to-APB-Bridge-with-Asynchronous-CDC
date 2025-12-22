# AXI4-Lite to APB Bridge with Asynchronous CDC

This project implements a robust bridge between an **AXI4-Lite** master (fast clock domain) and an **APB** slave (slow clock domain). It features asynchronous FIFOs for safe Clock Domain Crossing (CDC) and a fully verifiable testbench.

## 1. System Data & Control Flow

This diagram illustrates how data flows from the AXI Master, through the CDC FIFOs, to the APB FSM, and back.

```mermaid
graph LR
    %% Styles
    classDef aclk fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:black;
    classDef pclk fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:black;
    classDef fifo fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5,color:black;
    classDef ext fill:#f5f5f5,stroke:#616161,stroke-width:1px,color:black;

    %% External Interfaces
    AXI_Master["AXI4-Lite Master<br/>(Testbench)"]:::ext
    APB_Slaves["APB Slaves<br/>(External / TB)"]:::ext

    %% ACLK Domain Subgraph
    subgraph ACLK_Domain [ACLK Domain]
        direction TB
        AXI_Slave["AXI Lite Slave FSM<br/>(axi_lite_slave.sv)"]:::aclk
    end

    %% PCLK Domain Subgraph
    subgraph PCLK_Domain [PCLK Domain]
        direction TB
        Arbiter["Arbiter Logic<br/>(axi_apb_bridge_top.sv)"]:::pclk
        APB_FSM["APB Master FSM<br/>(apb_master_fsm.sv)"]:::pclk
    end

    %% FIFOs (CDC)
    subgraph CDC [Clock Domain Crossing]
        WrCmd_FIFO(("Write Cmd FIFO<br/>(async_fifo.sv)")):::fifo
        RdCmd_FIFO(("Read Cmd FIFO<br/>(async_fifo.sv)")):::fifo
        WrRsp_FIFO(("Write Rsp FIFO<br/>(async_fifo.sv)")):::fifo
        RdRsp_FIFO(("Read Rsp FIFO<br/>(async_fifo.sv)")):::fifo
    end

    %% Flow Connections - Write Path
    AXI_Master -- AW, W --> AXI_Slave
    AXI_Slave -- Push Cmd --> WrCmd_FIFO
    WrCmd_FIFO -- Pop Cmd --> Arbiter
    Arbiter --> APB_FSM
    APB_FSM -- PADDR, PWDATA --> APB_Slaves
    
    %% Response Path
    APB_Slaves -- PREADY, PSLVERR, PRDATA --> APB_FSM
    APB_FSM -- Push Resp --> WrRsp_FIFO
    WrRsp_FIFO -- Pop Resp --> AXI_Slave
    AXI_Slave -- BRESP --> AXI_Master

    %% Flow Connections - Read Path
    AXI_Master -- AR --> AXI_Slave
    AXI_Slave -- Push Cmd --> RdCmd_FIFO
    RdCmd_FIFO -- Pop Cmd --> Arbiter
    Arbiter -.-> APB_FSM
    APB_FSM -- PRDATA --> RdRsp_FIFO
    RdRsp_FIFO -- Pop Data --> AXI_Slave
    AXI_Slave -- RDATA, RRESP --> AXI_Master
```
## End-to-End Transaction Logic

The diagrams below illustrate the complete data and control flow for both **Write** and **Read** transactions. They demonstrate how the Bridge translates protocols between the high-speed AXI4-Lite domain and the lower-speed APB domain.

### 1. Write Transaction Flow (Top Diagram)
This flow demonstrates a complete write operation:

- **Initiation:** The AXI4-Lite Master drives the write address (`AWADDR`) and write data (`WDATA`).
- **Translation:** The Bridge captures these signals and initiates an APB write cycle by asserting the select signal (`PSEL`), enable signal (`PENABLE`), and setting `PWRITE=1`.
- **Completion:** The APB Slave captures the data and asserts `PREADY`. The Bridge then completes the handshake by sending a write response (`BRESP`) back to the AXI Master.

### 2. Read Transaction Flow (Bottom Diagram)
This flow demonstrates a complete read operation:

- **Initiation:** The AXI4-Lite Master drives the read address (`ARADDR`).
- **Translation:** The Bridge initiates an APB read cycle by setting `PWRITE=0`. It waits for the peripheral to provide data.
- **Data Return:** The APB Slave places the requested data on `PRDATA` and asserts `PREADY`. The Bridge captures this data and drives it back to the AXI Master via the `RDATA` channel.
```mermaid
graph LR
    %% --- Nodes & Subgraphs ---
    subgraph AXI_Side [AXI4-Lite Master]
        direction TB
        AXI_M["AXI Write Logic"]
    end
    
    subgraph Bridge_Scope [AXI-to-APB Bridge]
        direction TB
        DUT["Bridge Control"]
    end

    subgraph APB_Side [APB Slave]
        direction TB
        APB_S["Register/Memory"]
    end

    %% --- Styles ---
    classDef master fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef bridge fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef slave fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    
    class AXI_M master;
    class DUT bridge;
    class APB_S slave;

    %% --- Step 1: AXI Request ---
    AXI_M -- "AWADDR, WDATA, WVALID" --> DUT
    DUT -. "AWREADY, WREADY" .-> AXI_M

    %% --- Step 2: APB Access ---
    DUT -- "PSEL, PENABLE, PADDR<br/>PWDATA, PWRITE=1" --> APB_S
    APB_S -. "PREADY, PSLVERR" .-> DUT

    %% --- Step 3: AXI Response ---
    DUT -- "BRESP, BVALID" --> AXI_M
    AXI_M -. "BREADY" .-> DUT
```

```mermaid
graph LR
    %% Definitions
    subgraph AXI_Side [AXI4-Lite Domain]
        direction TB
        AXI_M["AXI Master<br/>(Read Initiator)"]
    end
    
    subgraph Bridge_Scope [The Bridge]
        direction TB
        DUT["AXI-to-APB Bridge<br/>(Translation Logic)"]
    end

    subgraph APB_Side [APB Domain]
        direction TB
        APB_S["APB Slave<br/>(Target Register)"]
    end

    %% Styles
    classDef master fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef bridge fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef slave fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    
    class AXI_M master;
    class DUT bridge;
    class APB_S slave;

    %% --- PHASE 1: AXI Read Request ---
    %% Master sends Address
    AXI_M -- "ARADDR, ARVALID" --> DUT
    %% Bridge accepts
    DUT -. "ARREADY" .-> AXI_M

    %% --- PHASE 2: APB Read Transaction ---
    %% Bridge drives APB Read (PWRITE=0)
    DUT -- "PSEL, PENABLE, PADDR<br/>PWRITE=0" --> APB_S
    %% Slave returns Data and Status
    APB_S -. "PREADY, PRDATA, PSLVERR" .-> DUT

    %% --- PHASE 3: AXI Read Response ---
    %% Bridge sends Data back
    DUT -- "RDATA, RRESP, RVALID" --> AXI_M
    %% Master accepts response
    AXI_M -. "RREADY" .-> DUT
```
### 10. Asynchronous FIFO Design (CDC)

This diagram details the architecture of the **Asynchronous FIFO** used for safe Clock Domain Crossing. It ensures data integrity between the fast AXI domain and the slow APB domain using Gray-coded pointers.

* **Write Domain:** Manages the write pointer and checks for the `full` condition by comparing against the synchronized read pointer.
* **Read Domain:** Manages the read pointer and checks for the `empty` condition by comparing against the synchronized write pointer.
* **Synchronization:** Pointers are converted to Gray code this prevents multi-bit synchronization errors (metastability), and passed through 2-stage synchronizers (`sync_2ff`) to safely cross clock domains.
* **Comparator:** The Comparators are responsible for generating the status flags by comparing the local pointer against the synchronized pointer from the opposite domain.
      * Empty condition (Read Domain):

```mermaid
graph LR
    %% --- Subgraphs for Clock Domains ---
    subgraph Write_Domain [Write Clock Domain]
        direction TB
        WR_Logic["Write Ptr Logic<br/>(Counter)"]
        W_B2G["B2G Converter<br/>(Binary to Gray)"]
        W_Cmp{"Comparator<br/>(Check Full)"}
        RAM_WR["Dual-Port RAM<br/>(Write Port)"]
    end

    subgraph Read_Domain [Read Clock Domain]
        direction TB
        RD_Logic["Read Ptr Logic<br/>(Counter)"]
        R_B2G["B2G Converter<br/>(Binary to Gray)"]
        R_Cmp{"Comparator<br/>(Check Empty)"}
        RAM_RD["Dual-Port RAM<br/>(Read Port)"]
    end

    subgraph CDC_Sync [CDC Synchronization]
        direction TB
        Sync_W2R["2FF Synchronizer<br/>(W-Ptr to Read)"]
        Sync_R2W["2FF Synchronizer<br/>(R-Ptr to Write)"]
    end

    %% --- Styles ---
    classDef wr fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef rd fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef sync fill:#e0e0e0,stroke:#616161,stroke-width:2px,stroke-dasharray: 5 5;
    classDef cmp fill:#fff9c4,stroke:#fbc02d,stroke-width:2px; 

    class WR_Logic,RAM_WR,W_B2G wr;
    class RD_Logic,RAM_RD,R_B2G rd;
    class Sync_W2R,Sync_R2W sync;
    class W_Cmp,R_Cmp cmp;

    %% --- Write Path Connections ---
    Input_WR("wr_en, wr_data") --> WR_Logic
    WR_Logic -- "wptr_bin (addr)" --> RAM_WR
    Input_WR --> RAM_WR
    
    %% B2G & Sync Flow
    WR_Logic -- "wptr_bin" --> W_B2G
    W_B2G -- "wptr_gray" --> Sync_W2R
    
    %% Full Flag Generation (Comparator)
    W_B2G -- "wptr_gray" --> W_Cmp
    Sync_R2W -- "rptr_gray_sync" --> W_Cmp
    W_Cmp -- "Match = Full" --> Output_Full("Output: full")

    %% --- Read Path Connections ---
    Input_RD("rd_en") --> RD_Logic
    RD_Logic -- "rptr_bin (addr)" --> RAM_RD
    RAM_RD -- "rd_data" --> Output_Data("Output: rd_data")
    
    %% B2G & Sync Flow
    RD_Logic -- "rptr_bin" --> R_B2G
    R_B2G -- "rptr_gray" --> Sync_R2W

    %% Empty Flag Generation (Comparator)
    R_B2G -- "rptr_gray" --> R_Cmp
    Sync_W2R -- "wptr_gray_sync" --> R_Cmp
    R_Cmp -- "Match = Empty" --> Output_Empty("Output: empty")

    %% --- CDC Crossings (2FF) ---
    Sync_W2R -.-> R_Cmp
    Sync_R2W -.-> W_Cmp
