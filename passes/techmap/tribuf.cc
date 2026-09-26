/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  Copyright (C) 2012  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#include "kernel/yosys.h"
#include "kernel/sigtools.h"

USING_YOSYS_NAMESPACE
PRIVATE_NAMESPACE_BEGIN

struct TribufConfig {
	bool merge_mode;
	bool logic_mode;
	bool formal_mode;

	TribufConfig() {
		merge_mode = false;
		logic_mode = false;
		formal_mode = false;
	}
};

struct TribufWorker {
	Module *module;
	SigMap sigmap;
	const TribufConfig &config;

	TribufWorker(Module *module, const TribufConfig &config) : module(module), sigmap(module), config(config)
	{
	}

	static bool is_all_z(SigSpec sig)
	{
		for (auto bit : sig)
			if (bit != State::Sz)
				return false;
		return true;
	}

	// Move tri-state buffers that are nested in $mux/$pmux trees driving an
	// output port to the output of the tree, e.g.
	//
	//   assign pad = hold ? 1'b0 : (oe ? d : 1'bz);
	//
	// Without this, -logic would convert the inner buffer to logic, because
	// it does not drive the port itself, and the pad would lose its tri-state.
	//
	// Each mux whose data inputs are whole tri-state buffer outputs, all-z
	// constants or ordinary signals becomes a mux of the buffers' data inputs
	// followed by a single buffer, enabled whenever the selected input is
	// driven. This repeats until the buffers reach the output. Muxes that only
	// partly select a buffer or z are left alone.
	void fold_nested(dict<SigSpec, vector<Cell*>> &tribuf_cells, const pool<SigBit> &output_bits)
	{
		pool<SigBit> pad_bits = output_bits;
		dict<SigBit, int> drivers;
		for (auto wire : module->wires())
			if (wire->port_input)
				for (auto bit : sigmap(wire))
					pad_bits.insert(bit);
		for (auto cell : module->cells())
			for (auto &conn : cell->connections())
				if (cell->output(conn.first))
					for (auto bit : sigmap(conn.second))
						drivers[bit]++;

		dict<SigBit, Cell*> mux_drivers;
		for (auto cell : module->selected_cells())
			if (cell->type.in(ID($mux), ID($pmux)))
				for (auto bit : sigmap(cell->getPort(ID::Y)))
					mux_drivers[bit] = cell;

		// Muxes reachable backwards from an output port through data inputs.
		pool<Cell*> cone;
		std::vector<SigBit> queue(output_bits.begin(), output_bits.end());
		while (!queue.empty()) {
			SigBit bit = queue.back();
			queue.pop_back();
			auto it = mux_drivers.find(bit);
			if (it == mux_drivers.end() || cone.count(it->second))
				continue;
			cone.insert(it->second);
			for (auto port : {ID::A, ID::B})
				for (auto b : sigmap(it->second->getPort(port)))
					if (b.wire)
						queue.push_back(b);
		}

		pool<Cell*> folded;
		bool changed = true;
		while (changed) {
			changed = false;

			dict<SigSpec, Cell*> single_tribufs;
			for (auto &it : tribuf_cells) {
				bool internal = GetSize(it.second) == 1;
				for (auto bit : it.first)
					internal &= !pad_bits.count(bit) && drivers[bit] == 1;
				if (internal)
					single_tribufs[it.first] = it.second.front();
			}

			for (auto mux : cone) {
				if (folded.count(mux))
					continue;

				int width = mux->getParam(ID::WIDTH).as_int();
				SigSpec a = mux->getPort(ID::A), b = mux->getPort(ID::B);
				std::vector<SigSpec> inputs = {a};
				for (int i = 0; i < GetSize(b); i += width)
					inputs.push_back(b.extract(i, width));

				// Per data input: the value to select and whether it drives.
				SigSpec data, enable;
				bool nested = false, partial = false;
				for (auto &input : inputs) {
					auto tribuf = single_tribufs.find(sigmap(input));
					if (is_all_z(input)) {
						data.append(SigSpec(State::Sx, width));
						enable.append(State::S0);
						nested = true;
					} else if (tribuf != single_tribufs.end()) {
						Cell *t = tribuf->second;
						data.append(t->getPort(ID::A));
						enable.append(t->getPort(t->type == ID($tribuf) ? ID::EN : ID::E));
						nested = true;
					} else {
						for (auto bit : input)
							if (bit == State::Sz)
								partial = true;
						data.append(input);
						enable.append(State::S1);
					}
				}
				if (!nested || partial)
					continue;

				SigSpec sel = mux->getPort(ID::S);
				SigSpec en = mux->type == ID($mux) ?
					module->Mux(NEW_ID, enable[0], enable[1], sel) :
					module->Pmux(NEW_ID, enable[0], enable.extract(1, GetSize(enable) - 1), sel);

				SigSpec y = mux->getPort(ID::Y);
				SigSpec muxout = module->addWire(NEW_ID, width);
				mux->setPort(ID::A, data.extract(0, width));
				mux->setPort(ID::B, data.extract(width, GetSize(data) - width));
				mux->setPort(ID::Y, muxout);

				for (auto bit : sigmap(muxout))
					drivers[bit]++;
				Cell *tribuf = module->addTribuf(NEW_ID, muxout, en, y);
				tribuf->set_src_attribute(mux->get_src_attribute());
				tribuf_cells[sigmap(y)].push_back(tribuf);
				module->design->scratchpad_set_bool("tribuf.added_something", true);

				folded.insert(mux);
				changed = true;
			}
		}
	}

	void run()
	{
		dict<SigSpec, vector<Cell*>> tribuf_cells;
		pool<SigBit> output_bits;

		if (config.logic_mode || config.formal_mode)
			for (auto wire : module->wires())
				if (wire->port_output)
					for (auto bit : sigmap(wire))
						output_bits.insert(bit);

		for (auto cell : module->selected_cells())
		{
			if (cell->type == ID($tribuf))
				tribuf_cells[sigmap(cell->getPort(ID::Y))].push_back(cell);

			if (cell->type == ID($_TBUF_))
				tribuf_cells[sigmap(cell->getPort(ID::Y))].push_back(cell);

			if (cell->type.in(ID($mux), ID($_MUX_)))
			{
				IdString en_port = cell->type == ID($mux) ? ID::EN : ID::E;
				IdString tri_type = cell->type == ID($mux) ? ID($tribuf) : ID($_TBUF_);

				if (is_all_z(cell->getPort(ID::A)) && is_all_z(cell->getPort(ID::B))) {
					module->remove(cell);
					continue;
				}

				if (is_all_z(cell->getPort(ID::A))) {
					cell->setPort(ID::A, cell->getPort(ID::B));
					cell->setPort(en_port, cell->getPort(ID::S));
					cell->unsetPort(ID::B);
					cell->unsetPort(ID::S);
					cell->type = tri_type;
					tribuf_cells[sigmap(cell->getPort(ID::Y))].push_back(cell);
					module->design->scratchpad_set_bool("tribuf.added_something", true);
					continue;
				}

				if (is_all_z(cell->getPort(ID::B))) {
					cell->setPort(en_port, module->Not(NEW_ID, cell->getPort(ID::S)));
					cell->unsetPort(ID::B);
					cell->unsetPort(ID::S);
					cell->type = tri_type;
					tribuf_cells[sigmap(cell->getPort(ID::Y))].push_back(cell);
					module->design->scratchpad_set_bool("tribuf.added_something", true);
					continue;
				}
			}
		}

		if (config.logic_mode && !config.formal_mode)
			fold_nested(tribuf_cells, output_bits);

		if (config.merge_mode || config.logic_mode || config.formal_mode)
		{
			for (auto &it : tribuf_cells)
			{
				bool no_tribuf = false;

				if (config.logic_mode && !config.formal_mode) {
					no_tribuf = true;
					for (auto bit : it.first)
						if (output_bits.count(bit))
							no_tribuf = false;
				}

				if (config.formal_mode)
					no_tribuf = true;

				if (GetSize(it.second) <= 1 && !no_tribuf)
					continue;

				if (config.formal_mode && GetSize(it.second) >= 2) {
					for (auto cell : it.second) {
						SigSpec others_s;

						for (auto other_cell : it.second) {
							if (other_cell == cell)
								continue;
							else if (other_cell->type == ID($tribuf))
								others_s.append(other_cell->getPort(ID::EN));
							else
								others_s.append(other_cell->getPort(ID::E));
						}

						auto cell_s = cell->type == ID($tribuf) ? cell->getPort(ID::EN) : cell->getPort(ID::E);

						auto other_s = module->ReduceOr(NEW_ID, others_s);

						auto conflict = module->And(NEW_ID, cell_s, other_s);

						std::string name = stringf("$tribuf_conflict$%s", cell->name.unescape());
						auto assert_cell = module->addAssert(name, module->Not(NEW_ID, conflict), SigSpec(true));

						assert_cell->set_src_attribute(cell->get_src_attribute());
						assert_cell->set_bool_attribute(ID::keep);

						module->design->scratchpad_set_bool("tribuf.added_something", true);
					}
				}

				SigSpec pmux_b, pmux_s;
				for (auto cell : it.second) {
					if (cell->type == ID($tribuf))
						pmux_s.append(cell->getPort(ID::EN));
					else
						pmux_s.append(cell->getPort(ID::E));
					pmux_b.append(cell->getPort(ID::A));
					module->remove(cell);
				}

				SigSpec muxout = GetSize(pmux_s) > 1 ? module->Pmux(NEW_ID, SigSpec(State::Sx, GetSize(it.first)), pmux_b, pmux_s) : pmux_b;

				if (no_tribuf)
					module->connect(it.first, muxout);
				else {
					module->addTribuf(NEW_ID, muxout, module->ReduceOr(NEW_ID, pmux_s), it.first);
					module->design->scratchpad_set_bool("tribuf.added_something", true);
				}
			}
		}
	}
};

struct TribufPass : public Pass {
	TribufPass() : Pass("tribuf", "infer tri-state buffers") { }
	void help() override
	{
		//   |---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|
		log("\n");
		log("    tribuf [options] [selection]\n");
		log("\n");
		log("This pass transforms $mux cells with 'z' inputs to tristate buffers.\n");
		log("\n");
		log("    -merge\n");
		log("        merge multiple tri-state buffers driving the same net\n");
		log("        into a single buffer.\n");
		log("\n");
		log("    -logic\n");
		log("        convert tri-state buffers that do not drive output ports\n");
		log("        to non-tristate logic. this option implies -merge.\n");
		log("        tri-state buffers nested in $mux or $pmux trees that drive\n");
		log("        output ports are first moved to the output of the tree.\n");
		log("\n");
		log("    -formal\n");
		log("        convert all tri-state buffers to non-tristate logic and\n");
		log("        add a formal assertion that no two buffers are driving the\n");
		log("        same net simultaneously. this option implies -merge.\n");
		log("\n");
	}
	void execute(std::vector<std::string> args, RTLIL::Design *design) override
	{
		TribufConfig config;

		log_header(design, "Executing TRIBUF pass.\n");

		size_t argidx;
		for (argidx = 1; argidx < args.size(); argidx++) {
			if (args[argidx] == "-merge") {
				config.merge_mode = true;
				continue;
			}
			if (args[argidx] == "-logic") {
				config.logic_mode = true;
				continue;
			}
			if (args[argidx] == "-formal") {
				config.formal_mode = true;
				continue;
			}
			break;
		}
		extra_args(args, argidx, design);

		for (auto module : design->selected_modules()) {
			TribufWorker worker(module, config);
			worker.run();
		}
	}
} TribufPass;

PRIVATE_NAMESPACE_END
