# AXI4-Lite-to-APB-Bridge-with-Asynchronous-CDC
Provide a small, easy-to-verify bridge that accepts AXI4-Lite transactions on the fast side and performs APB transfers to low-speed peripherals on the slow side. The bridge acts as an AXI4-Lite slave and as an APB master to selected peripherals, translating protocol and synchronizing clock domains. 

## Data & Control Flow

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
    
    %% --- השינוי כאן: הוספתי את PRDATA ---
    APB_Slaves -- PREADY, PSLVERR, PRDATA --> APB_FSM
    %% ------------------------------------

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
## Data Flow FIFO

```mermaid
graph LR
    %% ==========================================
    %% Styles & Definitions
    %% ==========================================
    classDef writeDomain fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:black;
    classDef readDomain  fill:#fff3e0,stroke:#ef6c00,stroke-width:2px,color:black;
    classDef memory      fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5,color:black;
    
    %% ==========================================
    %% 1. Write Side (ACLK Domain)
    %% ==========================================
    subgraph Write_Side ["Write Domain (ACLK)"]
        direction TB
        Input_Data[/"Data In (wdata)"/]:::writeDomain
        Write_En["Write Enable"]:::writeDomain
        Full_Flag{"Full Flag"}:::writeDomain
    end

    %% ==========================================
    %% 2. The Storage (Async Boundary)
    %% ==========================================
    FIFO_RAM[("Dual-Port RAM<br/>(Circular Buffer)")]:::memory

    %% ==========================================
    %% 3. Read Side (PCLK Domain)
    %% ==========================================
    subgraph Read_Side ["Read Domain (PCLK)"]
        direction TB
        Output_Data[/"Data Out (rdata)"/]:::readDomain
        Read_En["Read Enable"]:::readDomain
        Empty_Flag{"Empty Flag"}:::readDomain
    end

    %% ==========================================
    %% Connections
    %% ==========================================
    
    %% Write Operation
    Input_Data ==> FIFO_RAM
    Write_En --> |"Push"| FIFO_RAM
    FIFO_RAM -.-> |"Pointer Status"| Full_Flag
    Full_Flag -.-> |"Backpressure"| Write_En

    %% Read Operation
    FIFO_RAM ==> Output_Data
    Read_En --> |"Pop"| FIFO_RAM
    FIFO_RAM -.-> |"Pointer Status"| Empty_Flag
    Empty_Flag -.-> |"Wait"| Read_En

    %% ==========================================
    %% Link Styles
    %% ==========================================
    linkStyle 0,4 stroke-width:4px,fill:none,stroke:black; %% Data flow (Thick lines)
