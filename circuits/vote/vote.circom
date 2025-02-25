pragma circom  2.1.6;
include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/poseidon.circom";

include "../merkleTree/merkleTree.circom";

template CommitmentHasher() {
    signal input nullifier;
    signal input secret;
    signal output commitment;
    signal output nullifierHash;

    component commitmentHasher = Poseidon(2);
    component nullifierHasher = Poseidon(1);
    
    commitmentHasher.inputs[0] <== secret;
    commitmentHasher.inputs[1] <== nullifier;
    
    nullifierHasher.inputs[0] <== nullifier;

    commitment <== commitmentHasher.out;
    nullifierHash <== nullifierHasher.out;
}

// Verifies that commitment that corresponds to given secret and nullifier is included in the merkle tree of deposits
template Vote(depth) {
    signal input root;                 // public; Poseidon hash for the tree
    signal input nullifierHash;        // public; Poseidon Hash
    signal input vote;                 // public; not taking part in any computations; binds the vote to the proof
    signal input nullifier;            // private
    signal input secret;               // private
    signal input pathElements[depth];  // private
    signal input pathIndices[depth];   // private; 0 - left, 1 - right

    component commitmentHasher = CommitmentHasher();
    commitmentHasher.nullifier <== nullifier;
    commitmentHasher.secret <== secret;
    commitmentHasher.nullifierHash === nullifierHash;

    component tree = MerkleTreeVerifier(depth);

    component leafHasher = Poseidon(1);

    leafHasher.inputs[0] <== commitmentHasher.commitment;
    tree.leaf <== leafHasher.out;
    tree.merkleRoot <== root;
    for (var i = 0; i < depth; i++) {
        tree.merkleBranches[i] <== pathElements[i];
        tree.merkleOrder[i] <== pathIndices[i];
    }

    // Add hidden signals to make sure that tampering with a vote will invalidate the snark proof
    // Squares are used to prevent optimizer from removing those constraints

    signal voteSquare;
    voteSquare <== vote * vote;
}

component main {public [root, nullifierHash, vote]} = Vote(20);