pragma circom 2.1.6;

include "../bigInt/bigIntFunc.circom";
include "../bigInt/bigInt.circom";
include "../bigInt/bigIntOverflow.circom";
include "../bigInt/bigIntHelpers.circom";
include "./get.circom";
include "./powers/p256pows.circom";
include "./powers/p384pows.circom";
include "./powers/secp192r1pows.circom";
include "./powers/secp224r1pows.circom";
include "./powers/secp256k1pows.circom";
include "./powers/secp521r1pows.circom";
include "./powers/brainpoolP224r1pows.circom";
include "./powers/brainpoolP256r1pows.circom";
include "./powers/brainpoolP320r1pows.circom";
include "./powers/brainpoolP384r1pows.circom";
include "./powers/brainpoolP512r1pows.circom";
include "../utils/switcher.circom";
include "../bitify/bitify.circom";
include "../bitify/comparators.circom";
include "../int/arithmetic.circom";



//UNCONSTRAINED
template EllipticCurveAddUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P){
    signal input in1[2][CHUNK_NUMBER];
    signal input in2[2][CHUNK_NUMBER];
        
    signal output out[2][CHUNK_NUMBER];
    
    var dy[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, in2[1], in1[1], P);
    var dx[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, in2[0], in1[0], P);
    var dx_inv[200] = mod_inv(CHUNK_SIZE, CHUNK_NUMBER, dx, P);
    var lambda[200] = prod_mod(CHUNK_SIZE, CHUNK_NUMBER, dy, dx_inv, P);
    var lambda_sq[200] = prod_mod(CHUNK_SIZE, CHUNK_NUMBER, lambda, lambda, P);
    var x3[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, lambda_sq, in1[0], P), in2[0], P);
    var y3[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, prod_mod(CHUNK_SIZE, CHUNK_NUMBER, lambda, long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, in1[0], x3, P), P), in1[1], P);
    
    for (var i = 0; i < CHUNK_NUMBER; i++){
        out[0][i] <-- x3[i];
        out[1][i] <-- y3[i];
    }
}


//UNCONSTRAINED
template EllipticCurveDoubleUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P){
    signal input in[2][CHUNK_NUMBER];
    signal output out[2][CHUNK_NUMBER];
    var long_3[CHUNK_NUMBER];
    long_3[0] = 3;
    var lamb_num[200] = long_add_mod(CHUNK_SIZE, CHUNK_NUMBER, A, prod_mod(CHUNK_SIZE, CHUNK_NUMBER, long_3, prod_mod(CHUNK_SIZE, CHUNK_NUMBER, in[0], in[0], P), P), P);
    var lamb_denom[200] = long_add_mod(CHUNK_SIZE, CHUNK_NUMBER, in[1], in[1], P);
    var lamb[200] = prod_mod(CHUNK_SIZE, CHUNK_NUMBER, lamb_num, mod_inv(CHUNK_SIZE, CHUNK_NUMBER, lamb_denom, P), P);
    var x3[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, prod_mod(CHUNK_SIZE, CHUNK_NUMBER, lamb, lamb, P), long_add_mod(CHUNK_SIZE, CHUNK_NUMBER, in[0], in[0], P), P);
    var y3[200] = long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, prod_mod(CHUNK_SIZE, CHUNK_NUMBER, lamb, long_sub_mod(CHUNK_SIZE, CHUNK_NUMBER, in[0], x3, P), P), in[1], P);
    
    for (var i = 0; i < CHUNK_NUMBER; i++){
        out[0][i] <-- x3[i];
        out[1][i] <-- y3[i];
    }
}

// UNCONSTRAINED
template EllipticCurvePrecomputePipingerUnconstrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P, WINDOW_SIZE){
    signal input in[2][CHUNK_NUMBER];
        
    assert(WINDOW_SIZE == 3 || WINDOW_SIZE == 4);
    var PRECOMPUTE_NUMBER = 2 ** WINDOW_SIZE;
    
    signal output out[PRECOMPUTE_NUMBER][2][CHUNK_NUMBER];
    
    component getDummy = EllipticCurveGetDummy(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
    out[0] <== getDummy.dummyPoint;
    
    out[1] <== in;
    
    component doublers[PRECOMPUTE_NUMBER \ 2 - 1];
    component adders  [PRECOMPUTE_NUMBER \ 2 - 1];
    
    for (var i = 2; i < PRECOMPUTE_NUMBER; i++){
        if (i % 2 == 0){
            doublers[i \ 2 - 1] = EllipticCurveDoubleUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
            doublers[i \ 2 - 1].in <== out[i \ 2];
            doublers[i \ 2 - 1].out ==> out[i];
            
        }
        else {
            adders[i \ 2 - 1] = EllipticCurveAddUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
            adders[i \ 2 - 1].in1 <== out[1];
            adders[i \ 2 - 1].in2 <== out[i - 1];
            adders[i \ 2 - 1].out ==> out[i];
        }
    }
}

// UNCONSTRAINED
template EllipticCurveScalarMultUnconstrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P, WINDOW_SIZE){
    
    assert (WINDOW_SIZE == 4);
    signal input in[2][CHUNK_NUMBER];
    signal input scalar[CHUNK_NUMBER];
        
    signal output out[2][CHUNK_NUMBER];
    
    component precompute = EllipticCurvePrecomputePipingerUnconstrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P, WINDOW_SIZE);
    precompute.in <== in;
    
    
    var PRECOMPUTE_NUMBER = 2 ** WINDOW_SIZE;
    var DOUBLERS_NUMBER = CHUNK_SIZE * CHUNK_NUMBER - WINDOW_SIZE;
    var ADDERS_NUMBER = CHUNK_SIZE * CHUNK_NUMBER \ WINDOW_SIZE;
    
    
    component doublers[DOUBLERS_NUMBER];
    component adders  [ADDERS_NUMBER - 1];
    component bits2Num[ADDERS_NUMBER];
    component num2Bits[CHUNK_NUMBER];
    
    component getDummy = EllipticCurveGetDummy(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
    
    signal scalarBits[CHUNK_NUMBER * CHUNK_SIZE];
    
    for (var i = 0; i < CHUNK_NUMBER; i++){
        num2Bits[i] = Num2Bits(CHUNK_SIZE);
        num2Bits[i].in <== scalar[i];
        for (var j = 0; j < CHUNK_SIZE; j++){
            scalarBits[CHUNK_NUMBER * CHUNK_SIZE - CHUNK_SIZE * (i + 1) + j] <== num2Bits[i].out[CHUNK_SIZE - 1 - j];
        }
    }
    
    signal resultingPoints[ADDERS_NUMBER + 1][2][CHUNK_NUMBER];
    signal additionPoints[ADDERS_NUMBER][2][CHUNK_NUMBER];
    
    
    component isZeroResult[ADDERS_NUMBER];
    component isZeroAddition[ADDERS_NUMBER];
    
    component partsEqual[ADDERS_NUMBER][PRECOMPUTE_NUMBER];
    component getSum[ADDERS_NUMBER][2][CHUNK_NUMBER];
    
    
    component doubleSwitcher[DOUBLERS_NUMBER][2][CHUNK_NUMBER];
    
    component resultSwitcherAddition[DOUBLERS_NUMBER][2][CHUNK_NUMBER];
    component resultSwitcherDoubling[DOUBLERS_NUMBER][2][CHUNK_NUMBER];
    
    resultingPoints[0] <== precompute.out[0];
    
    for (var i = 0; i < CHUNK_NUMBER * CHUNK_SIZE; i += WINDOW_SIZE){
        bits2Num[i \ WINDOW_SIZE] = Bits2Num(WINDOW_SIZE);
        for (var j = 0; j < WINDOW_SIZE; j++){
            bits2Num[i \ WINDOW_SIZE].in[j] <== scalarBits[i + (WINDOW_SIZE - 1) - j];
        }
        
        isZeroResult[i \ WINDOW_SIZE] = IsEqual();
        isZeroResult[i \ WINDOW_SIZE].in[0] <== resultingPoints[i \ WINDOW_SIZE][0][0];
        isZeroResult[i \ WINDOW_SIZE].in[1] <== getDummy.dummyPoint[0][0];
        
        if (i != 0){
            for (var j = 0; j < WINDOW_SIZE; j++){
                doublers[i + j - WINDOW_SIZE] = EllipticCurveDoubleUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
                
                // if input == 0, double gen, result - zero
                // if input != 0, double res window times, result - doubling result
                if (j == 0){
                    for (var axis_idx = 0; axis_idx < 2; axis_idx++){
                        for (var coor_idx = 0; coor_idx < CHUNK_NUMBER; coor_idx++){
                            
                            doubleSwitcher[i \ WINDOW_SIZE - 1][axis_idx][coor_idx] = Switcher();
                            doubleSwitcher[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].bool <== isZeroResult[i \ WINDOW_SIZE].out;
                            doubleSwitcher[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[0] <== getDummy.dummyPoint[axis_idx][coor_idx];
                            doubleSwitcher[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[1] <== resultingPoints[i \ WINDOW_SIZE][axis_idx][coor_idx];
                            
                            doublers[i + j - WINDOW_SIZE].in[axis_idx][coor_idx] <== doubleSwitcher[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].out[1];
                        }
                    }
                }
                else {
                    doublers[i + j - WINDOW_SIZE].in <== doublers[i + j - 1 - WINDOW_SIZE].out;
                }
            }
        }
        
        // Setting components
        for (var axis_idx = 0; axis_idx < 2; axis_idx++){
            for (var coor_idx = 0; coor_idx < CHUNK_NUMBER; coor_idx++){
                getSum[i \ WINDOW_SIZE][axis_idx][coor_idx] = GetSumOfNElements(PRECOMPUTE_NUMBER);
            }
        }
        
        // Each sum is sum of all precomputed coordinates * isEqual result (0 + 0 + 1 * coordinate[][] + .. + 0)
        
        for (var point_idx = 0; point_idx < PRECOMPUTE_NUMBER; point_idx++){
            partsEqual[i \ WINDOW_SIZE][point_idx] = IsEqual();
            partsEqual[i \ WINDOW_SIZE][point_idx].in[0] <== point_idx;
            partsEqual[i \ WINDOW_SIZE][point_idx].in[1] <== bits2Num[i \ WINDOW_SIZE].out;
            for (var axis_idx = 0; axis_idx < 2; axis_idx++){
                for (var coor_idx = 0; coor_idx < CHUNK_NUMBER; coor_idx++){
                    getSum[i \ WINDOW_SIZE][axis_idx][coor_idx].in[point_idx] <== partsEqual[i \ WINDOW_SIZE][point_idx].out * precompute.out[point_idx][axis_idx][coor_idx];
                }
            }
        }
        
        // Setting results in point
        for (var axis_idx = 0; axis_idx < 2; axis_idx++){
            for (var coor_idx = 0; coor_idx < CHUNK_NUMBER; coor_idx++){
                additionPoints[i \ WINDOW_SIZE][axis_idx][coor_idx] <== getSum[i \ WINDOW_SIZE][axis_idx][coor_idx].out;
            }
        }
        
        if (i == 0){
            
            resultingPoints[i \ WINDOW_SIZE + 1] <== additionPoints[i \ WINDOW_SIZE];
            
        } else {
            
            adders[i \ WINDOW_SIZE - 1] = EllipticCurveAddUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
            
            adders[i \ WINDOW_SIZE - 1].in1 <== doublers[i - 1].out;
            adders[i \ WINDOW_SIZE - 1].in2 <== additionPoints[i \ WINDOW_SIZE];
            
            isZeroAddition[i \ WINDOW_SIZE] = IsEqual();
            isZeroAddition[i \ WINDOW_SIZE].in[0] <== additionPoints[i \ WINDOW_SIZE][0][0];
            isZeroAddition[i \ WINDOW_SIZE].in[1] <== getDummy.dummyPoint[0][0];
            
            // isZeroAddition / isZeroResult
            // 0 0 -> adders Result
            // 0 1 -> additionPoints
            // 1 0 -> doubling result
            // 1 1 -> 0
            
            for (var axis_idx = 0; axis_idx < 2; axis_idx++){
                for (var coor_idx = 0; coor_idx < CHUNK_NUMBER; coor_idx++){
                    resultSwitcherAddition[i \ WINDOW_SIZE - 1][axis_idx][coor_idx] = Switcher();
                    resultSwitcherDoubling[i \ WINDOW_SIZE - 1][axis_idx][coor_idx] = Switcher();
                    
                    resultSwitcherAddition[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].bool <== isZeroAddition[i \ WINDOW_SIZE].out;
                    resultSwitcherAddition[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[0] <== adders[i \ WINDOW_SIZE - 1].out[axis_idx][coor_idx];
                    resultSwitcherAddition[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[1] <== doublers[i - 1].out[axis_idx][coor_idx];
                    
                    resultSwitcherDoubling[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].bool <== isZeroResult[i \ WINDOW_SIZE].out;
                    resultSwitcherDoubling[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[0] <== additionPoints[i \ WINDOW_SIZE][axis_idx][coor_idx];
                    resultSwitcherDoubling[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].in[1] <== resultSwitcherAddition[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].out[0];
                    
                    resultingPoints[i \ WINDOW_SIZE + 1][axis_idx][coor_idx] <== resultSwitcherDoubling[i \ WINDOW_SIZE - 1][axis_idx][coor_idx].out[1];
                }
            }
        }
    }
    out <== resultingPoints[ADDERS_NUMBER];
}

//UNCONSTRAINED
template EllipicCurveScalarGeneratorMultUnconstrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P){
    
    signal input scalar[CHUNK_NUMBER];
        
    signal output out[2][CHUNK_NUMBER];
    
    var STRIDE = 8;
    var parts = CHUNK_NUMBER * CHUNK_SIZE \ STRIDE;
    
    var powers[parts][2 ** STRIDE][2][CHUNK_NUMBER];
    
    if (CHUNK_NUMBER == 4){
        if (P[0] == 18446744069414583343 && P[1] == 18446744073709551615 && P[2] == 18446744073709551615 && P[3] == 18446744073709551615){
            powers = get_g_pow_stride8_table_secp256k1(CHUNK_SIZE, CHUNK_NUMBER);
        }
        if (P[0] == 2311270323689771895 && P[1] == 7943213001558335528 && P[2] == 4496292894210231666 && P[3] == 12248480212390422972){
            powers = get_g_pow_stride8_table_brainpoolP256r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
        if (P[0] == 18446744073709551615 && P[1] == 4294967295 && P[2] == 0 && P[3] == 18446744069414584321) {
            powers = get_g_pow_stride8_table_p256(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 8 && CHUNK_SIZE == 66){
        if (P[0] == 73786976294838206463 && P[1] == 73786976294838206463 && P[2] == 73786976294838206463 && P[3] == 73786976294838206463 && P[4] == 73786976294838206463 && P[5] == 73786976294838206463 && P[6] == 73786976294838206463 && P[7] == 576460752303423487){
            powers = get_g_pow_stride8_table_secp521r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 8 && CHUNK_SIZE == 64){
        if (P[0] == 2930260431521597683 && P[1] == 2918894611604883077 && P[2] == 12595900938455318758 && P[3] == 9029043254863489090 && P[4] == 15448363540090652785 && P[5] == 14641358191536493070 && P[6] == 4599554755319692295 && P[7] == 12312170373589877899){
            powers = get_g_pow_stride8_table_brainpoolP512r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 6){
        if (P[0] == 9747760000893709395 && P[1] == 12453481191562877553 && P[2] == 1347097566612230435 && P[3] == 1526563086152259252 && P[4] == 1107163671716839903 && P[5] == 10140169582434348328){
            powers = get_g_pow_stride8_table_brainpoolP384r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
        if (P[0] == 4294967295 && P[1] == 18446744069414584320 && P[2] == 18446744073709551614 && P[3] == 18446744073709551615 && P[4] == 18446744073709551615 && P[5] == 18446744073709551615){
            powers = get_g_pow_stride8_table_p384(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 7 && CHUNK_SIZE == 32){
        if (P[0] == 2127085823 && P[1] == 2547681781 && P[2] == 2963212119 && P[3] == 1976686471 && P[4] == 706228261 && P[5] == 641951366 && P[6] == 3619763370){
            powers = get_g_pow_stride8_table_brainpoolP224r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
        if (P[0] == 1 && P[1] == 0 && P[2] == 0 && P[3] == 4294967295 && P[4] == 4294967295 && P[5] == 4294967295 && P[6] == 4294967295){
            powers = get_g_pow_stride8_table_secp224r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 5 && CHUNK_SIZE == 64){
        if (P[0] == 18218206948094062119 && P[1] == 5733849700882443304 && P[2] == 17982820153128390127 && P[3] == 16229979505782022245 && P[4] == 15230689193496432567){
            powers = get_g_pow_stride8_table_brainpoolP320r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    if (CHUNK_NUMBER == 3 && CHUNK_SIZE == 64){
        if (P[0] == 18446744073709551615 && P[1] == 18446744073709551614 && P[2] == 18446744073709551615){
            powers = get_g_pow_stride8_table_secp192r1(CHUNK_SIZE, CHUNK_NUMBER);
        }
    }
    
    component num2bits[CHUNK_NUMBER];
    for (var i = 0; i < CHUNK_NUMBER; i++){
        num2bits[i] = Num2Bits(CHUNK_SIZE);
        num2bits[i].in <== scalar[i];
    }
    component bits2num[parts];
    for (var i = 0; i < parts; i++){
        bits2num[i] = Bits2Num(STRIDE);
        for (var j = 0; j < STRIDE; j++){
            bits2num[i].in[j] <== num2bits[(i * STRIDE + j) \ CHUNK_SIZE].out[(i * STRIDE + j) % CHUNK_SIZE];
        }
    }

    component getDummy = EllipticCurveGetDummy(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
    component getSecondDummy = EllipticCurveDoubleUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);
    getSecondDummy.in <== getDummy.dummyPoint;

    component equal[parts][2 ** STRIDE];
    signal resultCoordinateComputation[parts][2 ** STRIDE][2][CHUNK_NUMBER];
    for (var i = 0; i < parts; i++){
        for (var j = 0; j < 2 ** STRIDE; j++){
            equal[i][j] = IsEqual();
            equal[i][j].in[0] <== j;
            equal[i][j].in[1] <== bits2num[i].out;
            
            if (j == 0 && i % 2 == 0){
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][0][axis_idx] <== equal[i][j].out * getDummy.dummyPoint[0][axis_idx];
                }
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][1][axis_idx] <== equal[i][j].out * getDummy.dummyPoint[1][axis_idx];
                }
            }
            if (j == 0 && i % 2 == 1){
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][0][axis_idx] <== equal[i][j].out * getSecondDummy.out[0][axis_idx];
                }
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][1][axis_idx] <== equal[i][j].out * getSecondDummy.out[1][axis_idx];
                }
            }
            if (j != 0) {
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][0][axis_idx] <== equal[i][j].out * powers[i][j][0][axis_idx];
                }
                for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                    resultCoordinateComputation[i][j][1][axis_idx] <== equal[i][j].out * powers[i][j][1][axis_idx];
                }
            }
        }
    }
    
    component getSumOfNElements[parts][2][CHUNK_NUMBER];
    for (var i = 0; i < parts; i++){
        for (var j = 0; j < 2; j++){
            for (var axis_idx = 0; axis_idx < CHUNK_NUMBER; axis_idx++){
                getSumOfNElements[i][j][axis_idx] = GetSumOfNElements(2 ** STRIDE);
                for (var stride_idx = 0; stride_idx < 2 ** STRIDE; stride_idx++){
                    getSumOfNElements[i][j][axis_idx].in[stride_idx] <== resultCoordinateComputation[i][stride_idx][j][axis_idx];
                }
            }
        }
    }
    
    signal additionPoints[parts][2][CHUNK_NUMBER];
    for (var part_idx = 0; part_idx < parts; part_idx++){
        for (var i = 0; i < 2; i++){
            for (var j = 0; j < CHUNK_NUMBER; j++){
                additionPoints[part_idx][i][j] <== getSumOfNElements[part_idx][i][j].out;
            }
        }
    }
    
    component adders[parts - 1];

    component isFirstDummyLeft[parts - 1];
    component isSecondDummyLeft[parts - 1];
    
    component isFirstDummyRight[parts - 1];
    component isSecondDummyRight[parts - 1];
    
    
    signal resultingPointsLeft[parts][2][CHUNK_NUMBER];
    signal resultingPointsLeft2[parts][2][CHUNK_NUMBER];
    signal resultingPointsRight[parts][2][CHUNK_NUMBER];
    signal resultingPointsRight2[parts][2][CHUNK_NUMBER];
    signal resultingPoints[parts][2][CHUNK_NUMBER];
    
    component switcherLeft[parts][2][CHUNK_NUMBER];
    component switcherRight[parts][2][CHUNK_NUMBER];
    
    
    for (var i = 0; i < parts - 1; i++){
        adders[i] = EllipticCurveAddUncostrained(CHUNK_SIZE, CHUNK_NUMBER, A, B, P);

        isFirstDummyLeft[i] = IsEqual();
        isFirstDummyLeft[i].in[0] <== getDummy.dummyPoint[0][0];
        isSecondDummyLeft[i] = IsEqual();
        isSecondDummyLeft[i].in[0] <== getSecondDummy.out[0][0];

        isFirstDummyRight[i] = IsEqual();
        isFirstDummyRight[i].in[0] <== getDummy.dummyPoint[0][0];
        isSecondDummyRight[i] = IsEqual();
        isSecondDummyRight[i].in[0] <== getSecondDummy.out[0][0];

        
        
        if (i == 0){
            isFirstDummyLeft[i].in[1] <== additionPoints[i][0][0];
            isSecondDummyLeft[i].in[1] <== additionPoints[i][0][0];
            isFirstDummyRight[i].in[1] <== additionPoints[i + 1][0][0];
            isSecondDummyRight[i].in[1] <== additionPoints[i + 1][0][0];
            adders[i].in1 <== additionPoints[i];
            adders[i].in2 <== additionPoints[i + 1];
               
            // 0 0 -> adders
            // 0 1 -> left
            // 1 0 -> right
            // 1 1 -> right
            for (var axis_idx = 0; axis_idx < 2; axis_idx++){
                for (var j = 0; j < CHUNK_NUMBER; j++){
                    
                    switcherRight[i][axis_idx][j] = Switcher();
                    switcherRight[i][axis_idx][j].bool <== isSecondDummyRight[i].out + isFirstDummyRight[i].out;
                    switcherRight[i][axis_idx][j].in[0] <== adders[i].out[axis_idx][j];
                    switcherRight[i][axis_idx][j].in[1] <== additionPoints[i][axis_idx][j];
                    
                    switcherLeft[i][axis_idx][j] = Switcher();
                    switcherLeft[i][axis_idx][j].bool <== isSecondDummyLeft[i].out + isFirstDummyLeft[i].out;
                    switcherLeft[i][axis_idx][j].in[0] <== additionPoints[i + 1][axis_idx][j];
                    switcherLeft[i][axis_idx][j].in[1] <== switcherRight[i][axis_idx][j].out[0];
                    
                    resultingPoints[i][axis_idx][j] <== switcherLeft[i][axis_idx][j].out[1];
                }
            }
            
        } else {
            isFirstDummyLeft[i].in[1] <== resultingPoints[i - 1][0][0];
            isSecondDummyLeft[i].in[1] <== resultingPoints[i - 1][0][0];
            isFirstDummyRight[i].in[1] <== additionPoints[i + 1][0][0];
            isSecondDummyRight[i].in[1] <== additionPoints[i + 1][0][0];

            adders[i].in1 <== resultingPoints[i - 1];
            adders[i].in2 <== additionPoints[i + 1];
            
            // 0 0 -> adders
            // 0 1 -> left
            // 1 0 -> right
            // 1 1 -> right
            for (var axis_idx = 0; axis_idx < 2; axis_idx++){
                for (var j = 0; j < CHUNK_NUMBER; j++){
                    
                    switcherRight[i][axis_idx][j] = Switcher();
                    switcherRight[i][axis_idx][j].bool <== isSecondDummyRight[i].out + isFirstDummyRight[i].out;
                    switcherRight[i][axis_idx][j].in[0] <== adders[i].out[axis_idx][j];
                    switcherRight[i][axis_idx][j].in[1] <== resultingPoints[i - 1][axis_idx][j];
                    
                    switcherLeft[i][axis_idx][j] = Switcher();
                    switcherLeft[i][axis_idx][j].bool <== isSecondDummyLeft[i].out + isFirstDummyLeft[i].out;
                    switcherLeft[i][axis_idx][j].in[0] <== additionPoints[i + 1][axis_idx][j];
                    switcherLeft[i][axis_idx][j].in[1] <== switcherRight[i][axis_idx][j].out[0];
                    
                    resultingPoints[i][axis_idx][j] <== switcherLeft[i][axis_idx][j].out[1];
                }
            }
        }
    }
    out <== resultingPoints[parts - 2];  
}
