
dAL <- function(t, y, parms) {
	.Call('sourceCpp_0_dAL',  PACKAGE='phydynR', t, y, parms)
}

simulateTreeCpp2 <- function(times
		 ,  Fs
		 ,  Gs
		 ,  Ys
		 , As
		 , sortedCoHeights 
		 , sortedSampleHeights 
		 , sortedSampleStates
		 , maxSampleTime
		 , m
		 , finiteSizeCorrection
		 , DEMES) {
	.Call('sourceCpp_2_simulateTreeCpp2',  PACKAGE='phydynR', times
		 ,  Fs
		 ,  Gs
		 ,  Ys
		 , As
		 , sortedCoHeights 
		 , sortedSampleHeights 
		 , sortedSampleStates
		 , maxSampleTime
		 , m
		 , finiteSizeCorrection
		 , DEMES)
}

simulateTreeCpp3x0 <- function(times
		 ,  Fs
		 ,  Gs
		 ,  Ys
		 , sortedSampleHeights 
		 , sortedSampleStates
		 , maxSampleTime
		 , m
		 , finiteSizeCorrection
) {
	.Call('sourceCpp_simulateTreeCpp3x0',  PACKAGE='phydynR'
		 , times
		 ,  Fs
		 ,  Gs
		 ,  Ys
		 , sortedSampleHeights 
		 , sortedSampleStates
		 , maxSampleTime
		 , m
		 , finiteSizeCorrection
	)
}


colik2cpp <- function(heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition) {
	.Call(  'sourceCpp_0_colik2cpp', PACKAGE='phydynR'
	 , heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition
	)
}

colik3cpp <- function(heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition) {
	.Call(  'sourceCpp_0_colik3cpp', PACKAGE='phydynR'
	 , heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition
	)
}


updateWCpp <- function( W
  , psi_a 
  , utips
  , vtips
  , utipsW
  , vtipsW )
{
	.Call( 'sourceCpp_0_updateWCpp', PACKAGE='phydynR'
	  , W
	  , psi_a 
	  , utips
	  , vtips
	  , utipsW
	  , vtipsW
	)
}




sourceAttribMultiDemeCpp <- function(heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition, maxHeight) {
	.Call(  'sourceCpp_0_sourceAttribMultiDemeCpp', PACKAGE='phydynR'
	 , heights, Fs, Gs, Ys, eventIndicator, eventIndicatorNode, eventHeights, sortedSampleStates, daughters, n, Nnode, m, AgtYboundaryCondition, maxHeight
	)
}

