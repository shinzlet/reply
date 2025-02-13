require "./spec_helper"

module Reply
  describe CharReader do
    it "read chars" do
      reader = SpecHelper.char_reader

      reader.verify_read('a', expect: ['a'])
      reader.verify_read("Hello", expect: ["Hello"])
    end

    it "read ANSI escape sequence" do
      reader = SpecHelper.char_reader

      reader.verify_read("\e[A", expect: :up)
      reader.verify_read("\e[B", expect: :down)
      reader.verify_read("\e[C", expect: :right)
      reader.verify_read("\e[D", expect: :left)
      reader.verify_read("\e[3~", expect: :delete)
      reader.verify_read("\e[1;5A", expect: :ctrl_up)
      reader.verify_read("\e[1;5B", expect: :ctrl_down)
      reader.verify_read("\e[1;5C", expect: :ctrl_right)
      reader.verify_read("\e[1;5D", expect: :ctrl_left)
      reader.verify_read("\e[H", expect: :home)
      reader.verify_read("\e[F", expect: :end)
      reader.verify_read("\eOH", expect: :home)
      reader.verify_read("\eOF", expect: :end)
      reader.verify_read("\e[1~", expect: :home)
      reader.verify_read("\e[4~", expect: :end)

      reader.verify_read("\e\t", expect: :shift_tab)
      reader.verify_read("\e\r", expect: :alt_enter)
      reader.verify_read("\e", expect: :escape)
      reader.verify_read("\n", expect: :enter)
      reader.verify_read("\t", expect: :tab)

      reader.verify_read('\0', expect: [] of CharReader::Sequence)
      reader.verify_read('\u0001', expect: :ctrl_a)
      reader.verify_read('\u0003', expect: :ctrl_c)
      reader.verify_read('\u0004', expect: :ctrl_d)
      reader.verify_read('\u0005', expect: :ctrl_e)
      reader.verify_read('\u000e', expect: :ctrl_n)
      reader.verify_read('\u0010', expect: :ctrl_p)
      reader.verify_read('\u0018', expect: :ctrl_x)
      reader.verify_read('\u007F', expect: :back)
    end

    it "read large buffer" do
      reader = SpecHelper.char_reader(buffer_size: 1024)

      reader.verify_read(
        "a"*10_000,
        expect: ["a" * 1024]*9 + ["a"*(10_000 - 9*1024)]
      )
    end
  end
end
