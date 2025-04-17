import erlang

extension Term {
    /// A process identifier.
    public struct PID: Sendable, Hashable, Decodable {
        var pid: erlang_pid
        
        init(pid: erlang_pid) {
            self.pid = pid
        }
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_pids(&lhs.pid, &rhs.pid) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(pid.creation)
            hasher.combine(pid.num)
            hasher.combine(pid.serial)
            hasher.combine(Array(tuple: pid.node, start: \.0))
        }
        
        public init(from decoder: any Decoder) throws {
            guard let decoder = decoder as? __TermDecoder
            else { fatalError("PID cannot be decoded outside of TermDecoder") }
            
            try decoder.singleValueContainer()
            
            var pid = erlang_pid()
            ei_decode_pid(decoder.buffer.buff, &decoder.index, &pid)
            self.pid = pid
        }
    }
}
