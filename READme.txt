7/3/26
Above modules arent finalised and need to be tested first.
These modules are to integrate BRAM usage into the original code for simd tensor accelerator.
Current pipeline with BRAM:-
           accel_top
               │
        ┌──────┴──────┐
        │             │
      BRAM A        BRAM B
        │             │
        └─────┬───────┘
              │
           SIMD ARRAY
        ┌────┼────┼────┐
        │    │    │    │
     lane0 lane1 lane2 lane3
        │    │    │    │
        └────┴────┴────┘
             MAC units
