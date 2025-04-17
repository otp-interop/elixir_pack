import erlang

extension Term {
    public struct Port: Sendable, Hashable {
        var port: erlang_port
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_ports(&lhs.port, &rhs.port) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(port.creation)
            hasher.combine(port.id)
            hasher.combine(Array(tuple: port.node, start: \.0))
        }
    }
}
