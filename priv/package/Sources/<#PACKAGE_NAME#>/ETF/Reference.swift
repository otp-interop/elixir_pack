import erlang

extension Term {
    public struct Reference: Sendable, Hashable {
        var ref: erlang_ref
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            var lhs = lhs
            var rhs = rhs
            return ei_cmp_refs(&lhs.ref, &rhs.ref) == 0
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(ref.creation)
            hasher.combine(ref.len)
            hasher.combine(Array(tuple: ref.n, start: \.0))
            hasher.combine(Array(tuple: ref.node, start: \.0))
        }
    }
}
