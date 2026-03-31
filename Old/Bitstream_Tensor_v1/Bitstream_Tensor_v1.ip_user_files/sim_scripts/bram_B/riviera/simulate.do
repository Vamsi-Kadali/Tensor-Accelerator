transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+bram_B  -L xil_defaultlib -L xpm -L blk_mem_gen_v8_4_11 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.bram_B xil_defaultlib.glbl

do {bram_B.udo}

run 1000ns

endsim

quit -force
