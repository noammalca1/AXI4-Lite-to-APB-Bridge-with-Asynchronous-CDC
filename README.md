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

## 2. AXI4-Lite Handshake Diagram (Slave Side)

The bridge acts as an **AXI Slave**. It accepts address and data from the master and provides responses.

```mermaid
graph LR
    %% Definitions
    subgraph APB_Master_Node [Bridge: APB Master FSM]
        direction TB
        M_WR["Write Logic"]
        M_RD["Read Logic"]
    end

    subgraph APB_Slave_Node [APB Slave / Peripheral]
        direction TB
        S_WR["Write Logic<br/>(Register Update)"]
        S_RD["Read Logic<br/>(Data Output)"]
    end

    %% Styles
    classDef master fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef slave fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    class M_WR,M_RD master;
    class S_WR,S_RD slave;

    %% ==========================================
    %% WRITE CHANNEL (Logic)
    %% ==========================================
    M_WR -- "PADDR, PWDATA<br/>PSEL, PENABLE, PWRITE=1" --> S_WR
    S_WR -. "PREADY, PSLVERR" .-> M_WR

    %% ==========================================
    %% READ CHANNEL (Logic)
    %% ==========================================
    M_RD -- "PADDR<br/>PSEL, PENABLE, PWRITE=0" --> S_RD
    S_RD -. "PREADY, PRDATA, PSLVERR" .-> M_RD

```

## 3. APB Handshake Diagram (Master Side)

The bridge acts as an **APB Master**. It drives controls to the peripheral and waits for `PREADY`.

```mermaid
graph LR
    %% Definitions
    subgraph AXI_Master_Node [AXI Master]
        direction TB
        M_WR["Write Logic"]
        M_RD["Read Logic"]
    end

    subgraph AXI_Slave_Node [Bridge: AXI Slave Interface]
        direction TB
        S_WR["Write Channel FSM"]
        S_RD["Read Channel FSM"]
    end

    %% Styles
    classDef master fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef slave fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    class M_WR,M_RD master;
    class S_WR,S_RD slave;

    %% --- WRITE CHANNEL ---
    M_WR -- "AWADDR, AWVALID" --> S_WR
    S_WR -. "AWREADY" .-> M_WR
    
    M_WR -- "WDATA, WSTRB, WVALID" --> S_WR
    S_WR -. "WREADY" .-> M_WR

    S_WR -- "BRESP, BVALID" --> M_WR
    M_WR -. "BREADY" .-> S_WR

    %% --- READ CHANNEL ---
    M_RD -- "ARADDR, ARVALID" --> S_RD
    S_RD -. "ARREADY" .-> M_RD

    S_RD -- "RDATA, RRESP, RVALID" --> M_RD
    M_RD -. "RREADY" .-> S_RD
```
## 3. write

The bridge acts as an **APB Master**. It drives controls to the peripheral and waits for `PREADY`.

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
## 3. read

The bridge acts as an **APB Master**. It drives controls to the peripheral and waits for `PREADY`.

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
