STEPS = step0_repl step1_read_print step2_eval step3_env step4_if_fn_do step5_tco step6_file step7_quote step8_macros step9_try stepA_mal

.PHONY: all
all: $(STEPS)

# zig_opts += --release=safe
$(STEPS): %: %.zig reader.zig printer.zig
	zig build-exe $<

.PHONY: clean
clean:
	rm -rf .zig-cache/ *.o
	rm -f $(STEPS)
