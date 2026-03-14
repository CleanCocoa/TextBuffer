extension TextRope {
    internal mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&root) {
            root = root.shallowCopy()
        }
    }
}
