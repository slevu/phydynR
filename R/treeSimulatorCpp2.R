require(Rcpp)
require(inline)
#~ sourceCpp( 'dAL1.cpp')
#~ sourceCpp( 'treeSimulatorCpp2.cpp')
#~ sourceCpp( 'treeSimulatorCpp3.cpp')
#NOTE  co sim method for sampling co heights not ensure A>2 for each coheight



#' Generate a demographic model from input strings, optionally compiling as Cpp using Rcpp and optionally solving as SDEs
# should return func(theta,  t0, t1, res=1e3) -> list(times, F, G, Y)
build.demographic.process <- function( births,  nonDemeDynamics=NA,  migrations=NA, deaths=NA,  parameterNames = c(), rcpp = TRUE, sde=FALSE)
{
	if (is.vector(births) & length(births) > 1) stop('there must be exactly one expr for births or a square matrix of expressions for births')
	#~ 	if (is.vector(births)){
	#~ 		m <- 1
	#~ 	} else{
	#~ 		m <- nrow(births)
	#~ 	}
	if (is.vector(births) & (length(births)==1) ){
		bn <- names(births)
		births <- matrix( c( births, '0.', '0.', '0.'), nrow = 2, ncol = 2)
		colnames(births) = rownames(births) <- c(bn, 'V2')
	}
	if (!any(is.na(migrations))){
		if (is.vector(migrations) & (length(migrations)==1))
		{
			bn <- names(migrations)
			migrations <- matrix( c( migrations, '0.', '0.', '0.'), nrow = 2, ncol = 2)
			colnames(migrations) = rownames(migrations) <- c(bn,  'V2')
		}
	}
	if (is.vector(migrations) & !(length(migrations)==1)) stop('Migrations must be matrix or length 1 vector')
	if (is.vector(births) & !(length(births)==1) ) stop( 'Births must be matrix or length 1 vector' )
	demeNames <- rownames(births)
	m <- nrow(births)
	if ( any (is.na( nonDemeDynamics )) & length(nonDemeDynamics)==1 ){
		mm <- 0
		nonDemeNames <- NULL
	} else if ( any (is.na(nonDemeDynamics)) & length(nonDemeDynamics)>1){
		stop('NA values in nonDemeDynamics')
	} else{
		nonDemeNames <- names(nonDemeDynamics)
		mm <- length(nonDemeNames)
	}
	
	if (m==2 & length(deaths)==1 & demeNames[2]=='V2'){
		deaths <- c(deaths, V2='0.')
	}
	if (any(is.na(migrations))){
		migrations <- matrix('0.', nrow=m, ncol=m)
		rownames(migrations)=colnames(migrations)<- demeNames
	}
	if (any(is.na(deaths))){
		deaths <- rep('0.', m)
		names(deaths) <- demeNames
	}
	
	if (rcpp)
	{
		print(paste(date(), 'Compiling model...'))
		macros <- paste(collapse='\n', sapply(1:(m+mm) ,function(i){
			ii <- i -1 
			paste('#define' , c(demeNames, nonDemeNames)[i], paste(sep='', '(double)(X[', ii, '])' )) 
		}))
		
		if (length(parameterNames) > 0){
			macros <- paste(macros, sep='\n', 
			paste(collapse='\n'
				, sapply(1:length(parameterNames), function(i){
					ii <- i -1
					paste('#define' , parameterNames[i], paste(sep='', '(double)(PARMS[', ii, '])' )) 
				}))
				, '\n'
			)
		}
		
		## build F
		# also return row sum and col sum
		Fexprs <- as.vector(sapply(1:m, function(k) sapply(1:m, function(l)  
		{
			paste( sep=''
			 , 'F(', k-1, ',', l-1, ') = std::max(0., (double)('
			 , births[k,l]
			 , '))'
			)
		}
		) ))
		Fheader <- "
NumericVector X(x);
NumericVector PARMS(parms);
double T = as<double>(t);
int M = as<int>(m);
NumericMatrix F(M,M);
CharacterVector rcnames(demenames);
rownames(F) = rcnames;
colnames(F) = rcnames;"
		Fbody <- paste( sep='\n', Fheader , macros 
			, paste( paste(collapse=';\n', Fexprs)
				, ';\n NumericVector rsums(M); for(int k = 0; k <M; k++) rsums(k) = sum(F(k,_));\n'
				, 'NumericVector csums(M); for(int k = 0; k <M; k++) csums(k) = sum(F(_,k));\n'
				, 'return List::create(Named("F") = F, Named("rowsum") = rsums, Named("colsum") = csums);'
			)
		)
		
		Fcpp <<-  cxxfunction(
			signature(x="numeric"
				, t="numeric"
				, m = "integer"
				, parms="numeric"
				, demenames="character"),
			, plugin = 'Rcpp'
			, body = Fbody
		)
		
		
		
		## build G
		Gexprs <- as.vector(sapply(1:m, function(k) sapply(1:m, function(l)  
		{
			paste( sep=''
			 , 'G(', k-1, ',', l-1, ') = std::max(0., (double)('
			 , migrations[k,l]
			 , '))'
			)
		}
		) ))
		Gheader <- "
NumericVector X(x);
NumericVector PARMS(parms);
double T = as<double>(t);
int M = as<int>(m);
NumericMatrix G(M,M);
CharacterVector rcnames(demenames);
rownames(G) = rcnames;
colnames(G) = rcnames;"
		Gbody <- paste( sep='\n' , Gheader, macros
				, paste( paste(collapse=';\n', Gexprs)
				, ';\n NumericVector rsums(M); for(int k = 0; k <M; k++) rsums(k) = sum(G(k,_));\n'
				, 'NumericVector csums(M); for(int k = 0; k <M; k++) csums(k) = sum(G(_,k));\n'
				, 'return List::create(Named("G") = G, Named("rowsum") = rsums, Named("colsum") = csums);')
		)
		
		Gcpp <<-  cxxfunction(
			signature(x="numeric"
				, t="numeric"
				, m = "integer"
				, parms="numeric"
				, demenames="character"),
			, plugin = 'Rcpp'
			, body = Gbody
		)
		
		
		
		## deaths
		death_header <- '
NumericVector X(x);
NumericVector PARMS(parms);
double T = as<double>(t);
int M = as<int>(m);;
CharacterVector rcnames(demenames);
NumericVector deaths(M);
deaths.attr("names") = rcnames;
'
		death_exprs <- sapply( 1:length(deaths), function(i) {
			paste( sep='', 'deaths(', i-1, ') = std::max(0., ', deaths[i], ')' )
		})
		death_body <-paste(sep='\n', death_header, macros
		  ,  paste(collapse=';\n', death_exprs)
		  , ';\n return deaths;'
		)
		death.cpp <<-  cxxfunction(
			signature(x="numeric"
				, t="numeric"
				, m = "integer"
				, parms="numeric"
				, demenames="character"),
			, plugin = 'Rcpp'
			, body = death_body
		)
		
		
		## non deme dynamics
		if (mm > 0)
		{
			ndd_header <- '
	NumericVector X(x);
	NumericVector PARMS(parms);
	double T = as<double>(t);
	int MM = as<int>(mm);;
	CharacterVector rcnames(nondemenames);
	NumericVector ndd(MM);
	ndd.attr("names") = rcnames;
	'
			ndd_exprs <- sapply(1:length(nonDemeDynamics), function(i){
				paste(sep='', 'ndd(', i-1, ') = ', nonDemeDynamics[i] )
			})
			ndd_body <- paste(sep='\n', ndd_header, macros
			  , paste(collapse=';\n', ndd_exprs)
			  , ';\n return ndd; '
			)
			nonDemeDynamics.cpp <<-  cxxfunction(
				signature(x="numeric"
					, t="numeric"
					, mm = "integer"
					, parms="numeric"
					, nondemenames="character"),
				, plugin = 'Rcpp'
				, body = ndd_body
			)
		}
		
		##
		
		if (!sde) #ODE
		{
			.dx__solve.demographic.process <<- function(t, y, parms, ...) 
			{ #note parms is list
				.F <- Fcpp(y, t, m, unlist(parms), demeNames)
				.G <- Gcpp(y, t, m, unlist(parms), demeNames)
				.deaths <- death.cpp(y, t, m, unlist(parms), demeNames)
				dxdeme <- setNames(
				  .F$colsum + .G$colsum - .G$rowsum - .deaths
				 , demeNames
				)
				if (mm > 0)
				{
					.ndd <- nonDemeDynamics.cpp( y, t, mm, unlist(parms), nonDemeNames)
					dxnondeme <- setNames( 
					  nonDemeDynamics.cpp( y, t, mm, unlist(parms), nonDemeNames)
					  , nonDemeNames 
					)
				}else{
					dxnondeme <- NULL
				}
				
				list( c(dxdeme, dxnondeme) )
			}
			
			solve.demographic.process <- function( theta, x0, t0, t1, res = 1e3, integrationMethod='lsoda')
			{ # value : list(times, births, migrations, sizes )
				# NOTE x0 should be passed here in case there are estimated parameters related to initial conditions
				if (m == 2 & length(x0) == (1+mm) & demeNames[2]=='V2') x0 <- c(x0, V2 = 0)
				#reorder x0 if necessary
				if (length(x0)!=m + mm) stop(paste('initial conditons incorrect dimension', x0, m, mm) )
				if ( sum( !(c(demeNames, nonDemeNames) %in% names(x0)) )  > 0)  stop(paste('initial conditions vector incorrect names', names(x0), demeNames, nonDemeNames))
				y0 <- x0[c(demeNames, nonDemeNames)]
				
				#reorder theta if necessary
				#if ( length( setdiff( names(theta), parameterNames) ) > 0) stop(paste('Incorrect parameters included: ', setdiff( names(theta), parameterNames) )) #NOTE will allow extraneous parameters
				if ( length( setdiff(  parameterNames, names(theta)) ) > 0) stop(paste('Missing parameters: ', setdiff(  parameterNames, names(theta)) ))
				theta <- theta[parameterNames]
				
				times <- seq(t0, t1, length.out=res)
				ox <- ode(y=y0
				 , times
				 , func=.dx__solve.demographic.process
				 , parms = as.list(theta)
				 , method = integrationMethod)
				# note does not include first value, which is t0; 2nd value corresponds to root of tree
				Ys <- lapply( nrow(ox):1, function(i) setNames(pmax(0,ox[i, demeNames]), demeNames) ) 
				Fs <- lapply( nrow(ox):1, function(i) {
					Fcpp( ox[i,2:ncol(ox)], ox[i,1], m, unlist(theta), demeNames)$F
				}) 
				Gs <- lapply( nrow(ox):1, function(i) {
					Gcpp( ox[i,2:ncol(ox)], ox[i,1], m, unlist(theta), demeNames)$G
				})
				# include ox for debugging
				o <- list( times=rev(times), births=Fs, migrations=Gs, sizes=Ys , ox )
				class(o) <- c('tfgy', 'list')
				o
			}
		} else{ # SDE
			# solve using given timestep and euler method
			# interpret F & G as rates of process
			solve.demographic.process <- function( theta, x0, t0, t1, res = 1e3, integrationMethod=NA)
			{ # value : list(times, births, migrations, sizes )
				# NOTE x0 should be passed here in case there are estimated parameters related to initial conditions
				#reorder x0 if necessary
				if (m == 2 & length(x0) == 1 & demeNames[2]=='V2') x0 <- c(x0, V2 = 0)
				if (length(x0)!=m + mm) stop('initial conditons incorrect dimension', x0, m, mm) 
				if ( sum( !(c(demeNames, nonDemeNames) %in% names(x0)) )  > 0)  stop('initial conditions vector incorrect names', names(x0), demeNames, nonDemeNames)
				y0 <- x0[c(demeNames, nonDemeNames)]
				
				#reorder theta if necessary
				if ( length( setdiff( names(theta), parameterNames) ) > 0) stop('Incorrect parameters included: ', setdiff( names(theta), parameterNames) )
				if ( length( setdiff(  parameterNames, names(theta)) ) > 0) stop('Missing parameters: ', setdiff(  parameterNames, names(theta)) )
				theta <- theta[parameterNames]
				
				Fs <- list()
				Gs <- list()
				Ys <- list()
				times <- seq(t0, t1, length.out = res )
				Dt <- times[2] - times[1]
				x <- y0
				ox <- matrix(NA, nrow = res, ncol = 1 + m + mm )
				colnames(ox) <- c("time", demeNames, nonDemeNames)
				for (it in 1:res){
					Ys[[it]] <- setNames( pmax(0., x[demeNames] ), demeNames )
					t <- times[it]
					FF <- Fcpp( x, t, m, theta, demeNames)$F
					rF <- matrix( nrow=m, ncol = m, pmax(0, rnorm(m*m, mean = as.vector(FF)*Dt, sd = sqrt( as.vector(FF)*Dt)  ) ) )
					Fs[[it]] <- rF / Dt
					GG <- Gcpp( x, t, m, theta, demeNames)$G
					rG <- matrix( nrow=m, ncol = m, pmax(0, rnorm(m*m, mean = as.vector(GG)*Dt, sd = sqrt( as.vector(GG)*Dt)  ) ) )
					Gs[[it]] <- rG / Dt
					.deaths <- death.cpp(x, t, m, theta, demeNames)
					rdeaths <- pmax(0, rnorm(m, mean = .deaths * Dt, sd = sqrt(.deaths * Dt)   ) )
					stepx_demes <- colSums( rF) + colSums( rG ) - rowSums( rG ) - rdeaths
					if (mm > 0){
						.ndd <- nonDemeDynamics.cpp( x, t, mm, theta, nonDemeNames)
						r_ndd <- rnorm(mm, mean = .ndd*Dt, sd = sqrt(abs(.ndd*Dt)) ) 
					} else{
						.ndd <- c()
						r_ndd <- c()
					}
					stepx_nondemes <- r_ndd
					x <- setNames( pmax(0, x + c(stepx_demes, stepx_nondemes))
					  , c(demeNames, nonDemeNames) )
					ox[it, ] <- c( t, x )
				}
				
				
				# include ox for debugging
				o <- list( times=rev(times), births=rev(Fs), migrations=rev(Gs), sizes=rev(Ys) , ox )
				class(o) <- c('tfgy', 'list')
				o
			}
		}
		
		print(paste(date(), 'Model complete'))
	} else{ # inputs are R expressions (slow/avoid)
		#parse equations
		pbirths <- sapply( 1:m, function(k) 
			   sapply(1:m, function(l)
				 parse(text=births[k,l])
			))
		migrations[is.na(migrations)] <- '0'
		if (length(migrations)==1) migrations <- matrix('0', nrow=m, ncol=m)
		colnames(migrations)=rownames(migrations) <- demeNames
		pmigrations <- sapply( 1:m, function(k) 
			   sapply(1:m, function(l)
				 parse(text=migrations[k,l])
			))
		pdeaths <- sapply(1:m, function(k) parse(text=deaths[k]) )
		if (mm > 0) {
			pndd <- sapply(1:mm, function(k) parse(text=nonDemeDynamics[k]) )
		} else {
			pndd <- NA
		}
		
		.birth.matrix <- function( x, t, parms) 
		{
			with(as.list(x), 
			 t(matrix( sapply( 1:m^2, function(k){
					epb <- eval(pbirths[k])
					if (any(is.na(epb))) warning('NA/NaN values in births')
					epb[is.na(epb)] <- 0
					epb
				})
			  , nrow=m, ncol=m
			))) -> FF
			colnames(FF) = rownames(FF) <- demeNames
			FF
		}
		.migration.matrix <- function( x, t, parms) 
		{
			with(as.list(x), 
			 t(matrix( sapply( 1:m^2, function(k){
					epb <- eval(pmigrations[k])
					if (any(is.na(epb))) warning('NA/NaN values in migrations')
					epb[is.na(epb)] <- 0
					epb
				  })
				 , nrow=m, ncol=m
			))) -> GG
			colnames(GG) = rownames(GG) <- demeNames
			GG
		}
		tBirths <- function(x, t, parms)
		{
			colSums( .birth.matrix(x,t, parms) )
		}
		tMigrationsIn <- function(x,t, parms)
		{
			colSums( .migration.matrix(x, t, parms) )
		}
		tMigrationsOut <- function(x,t, parms)
		{
			rowSums( .migration.matrix(x, t, parms))
		}
		tDeaths <- function(x, t, parms) 
		{
			with(as.list(x, t), 
			  sapply(1:m, function(k) {
				epb <- eval(pdeaths[k]) 
				if (any(is.na(epb))) warning('NA/NaN values deaths')
				epb[is.na(epb)] <- 0
				epb
			  })
			) 
		}
		dNonDeme <- function(x, t, parms) 
		{
			with(as.list(x, t), 
			  sapply(1:mm, function(k) {
				epb <- eval(pndd[k]) 
				if (any(is.na(epb))) warning('NA/NaN values in dNonDeme')
				epb[is.na(epb)] <- 0
				epb
			  })  
			)
		}
		if (!sde){
			solve.demographic.process <- function( theta, x0, t0, t1, res = 1e3, integrationMethod='lsoda')
			{ # value : list(times, births, migrations, sizes )
				#reorder x0 if necessary
				## NOTE x0 should be passed here in case there are estimated parameters related to initial conditions
				if (m == 2 & length(x0) == (1+mm) & demeNames[2]=='V2') x0 <- c(x0, V2 = 0)
				#reorder x0 if necessary
				if (length(x0)!=m + mm) stop(paste('initial conditons incorrect dimension', x0, m, mm) )
				if ( sum( !(c(demeNames, nonDemeNames) %in% names(x0)) )  > 0)  stop(paste('initial conditions vector incorrect names', names(x0), demeNames, nonDemeNames))
				y0 <- x0[c(demeNames, nonDemeNames)]
								
				#reorder theta if necessary
				#if ( length( setdiff( names(theta), parameterNames) ) > 0) stop('Incorrect parameters included: ', setdiff( names(theta), parameterNames) )
				if ( length( setdiff(  parameterNames, names(theta)) ) > 0) stop('Missing parameters: ', setdiff(  parameterNames, names(theta)) )
				theta <- theta[parameterNames]
				parms <- as.list( theta  )
				
				dx <- function(t, y, parms, ...) 
				{
					dxdeme <- setNames( tBirths(y, t, parms) + tMigrationsIn(y, t, parms) - tMigrationsOut(y,t, parms) - tDeaths(y,t, parms), demeNames)
					if (mm > 0)
					{
						dxnondeme <- setNames( dNonDeme(y, t, parms), nonDemeNames )
					}else{
						dxnondeme <- NULL
					}
					
					list( c(dxdeme, dxnondeme) )
				}
				
				times <- seq(t0, t1, length.out=res)
				ox <- ode(y=y0, times, func=dx, parms=parms, method=integrationMethod)
				Ys <- lapply( nrow(ox):1, function(i) ox[i, demeNames] )
				Fs <- lapply( nrow(ox):1, function(i) .birth.matrix(ox[i,], ox[i,1], parms)  ) 
				Gs <- lapply( nrow(ox):1, function(i) .migration.matrix(ox[i,], ox[i,1], parms)  ) 
				
				# include ox for debugging
				o <- list( times=rev(times), births=Fs, migrations=Gs, sizes=Ys , ox )
				class(o) <- c('tfgy', 'list')
				o
			}
		} else{
			solve.demographic.process <- function( theta, x0, t0, t1, res = 1e3, integrationMethod=NA)
			{ # value : list(times, births, migrations, sizes )
				# NOTE x0 should be passed here in case there are estimated parameters related to initial conditions
				#reorder x0 if necessary
				if (m == 2 & length(x0) == 1 & demeNames[2]=='V2') x0 <- c(x0, V2 = 0)
				if (length(x0)!=m + mm) stop('initial conditons incorrect dimension', x0, m, mm) 
				if ( sum( !(c(demeNames, nonDemeNames) %in% names(x0)) )  > 0)  stop('initial conditions vector incorrect names', names(x0), demeNames, nonDemeNames)
				y0 <- x0[c(demeNames, nonDemeNames)]
				
				#reorder theta if necessary
				if ( length( setdiff( names(theta), parameterNames) ) > 0) stop('Incorrect parameters included: ', setdiff( names(theta), parameterNames) )
				if ( length( setdiff(  parameterNames, names(theta)) ) > 0) stop('Missing parameters: ', setdiff(  parameterNames, names(theta)) )
				theta <- theta[parameterNames]
				parms <- as.list( theta  )
				
				Fs <- list()
				Gs <- list()
				Ys <- list()
				times <- seq(t0, t1, length.out = res )
				Dt <- times[2] - times[1]
				x <- y0
				ox <- matrix(NA, nrow = res, ncol = 1 + m + mm )
				colnames(ox) <- c("time", demeNames, nonDemeNames)
				for (it in 1:res){
					Ys[[it]] <- setNames( pmax(0., x[demeNames] ), demeNames )
					t <- times[it]
					FF <- .birth.matrix(x, t, parms )
					rF <- matrix( nrow=m, ncol = m, pmax(0, rnorm(m*m, mean = as.vector(FF)*Dt, sd = sqrt( as.vector(FF)*Dt)  ) ) )
					Fs[[it]] <- rF / Dt
					GG <- .migration.matrix(x, t, parms)
					rG <- matrix( nrow=m, ncol = m, pmax(0, rnorm(m*m, mean = as.vector(GG)*Dt, sd = sqrt( as.vector(GG)*Dt)  ) ) )
					Gs[[it]] <- rG / Dt
					.deaths <- tDeaths( x, t, parms )
					rdeaths <- pmax(0, rnorm(m, mean = .deaths * Dt, sd = sqrt(.deaths * Dt)   ) )
					stepx_demes <- colSums( rF) + colSums( rG ) - rowSums( rG ) - rdeaths
					stepx_demes[is.na(stepx_demes)] <- 0
					if (mm > 0){
						.ndd <- dNonDeme( x, t, parms)
						r_ndd <- rnorm(mm, mean = .ndd*Dt, sd = sqrt(abs(.ndd*Dt)) ) 
						stepx_nondemes <- r_ndd
						stepx_nondemes[is.na(stepx_nondemes)] <- 0
					} else{
						.ndd <- c()
						r_ndd <- c()
						stepx_nondemes <- r_ndd
					}
					
					x <- setNames( pmax(0, x + c(stepx_demes, stepx_nondemes) )
					  , c(demeNames, nonDemeNames) )
					ox[it, ] <- c( t, x )
				}
				
				
				# include ox for debugging
				o <- list( times=rev(times), births=rev(Fs), migrations=rev(Gs), sizes=rev(Ys) , ox )
				class(o) <- c('tfgy', 'list')
				o
			}
		}
	}

	# return value is func
	class(solve.demographic.process) <- c('demographic.process', 'function')
	solve.demographic.process
}




##################################################################################
DatedTree <- function( phylo, sampleTimes, sampleStates=NULL, sampleStatesAnnotations=NULL, tol = 1e-6, minEdgeLength = 0){
	if (is.null(names(sampleTimes))) stop('sampleTimes vector must have names of tip labels')
	if (is.null(sampleStates) & !is.null(sampleStatesAnnotations) ) sampleStates <- .infer.sample.states.from.annotation(phylo, sampleStatesAnnotations)
	if (is.null(sampleStates) & is.null(sampleStatesAnnotations)) { sampleStates <- t(t( rep(1, length(phylo$tip.label)))) ; rownames( sampleStates) <- phylo$tip.label }
	if (is.null( rownames( sampleStates)))  rownames(sampleStates ) <- phylo$tip.label
	if (any(is.na(rownames(sampleStates)))) stop('sampleStates matrix must have row names of tip labels')
	if (!any(is.na(sampleStates))) if (!is.matrix( sampleStates)) stop('sampleStates must be a matrix (not a data.frame)')
	
	# resolve any multifurcations 
	phylo <- tryCatch( { multi2di( phylo ) }, error = function(e) phylo )
	
	phylo$sampleTimes <- sampleTimes[phylo$tip.label]
	phylo$sampleStates <- sampleStates[phylo$tip.label, ]
	if (is.vector(phylo$sampleStates)) phylo$sampleStates <- t(t( phylo$sampleStates))
	
	phylo$n = n <- length(sampleTimes)
	Nnode <- phylo$Nnode
	# compute heights, ensure consistency of sample times and branch lengths
	phylo$maxSampleTime   <- max(phylo$sampleTimes)
	heights <- rep(NA, (phylo$Nnode + length(phylo$tip.label)) )
	heights[1:length(phylo$sampleTimes)] <- phylo$maxSampleTime - phylo$sampleTimes
	curgen <- 1:length(phylo$sampleTimes)
	edgeLengthChange <- TRUE 
	while (edgeLengthChange)
	{
		edgeLengthChange <- FALSE
		while( length(curgen) > 0) { 
			nextgen <- c()
			icurgenedges <- which(  phylo$edge[,2] %in% curgen  )
			for (i in icurgenedges){
				u<- phylo$edge[i,1]
				v<- phylo$edge[i,2]
				if (!is.na(heights[u])){ # ensure branch lengths consistent
					if ( heights[u] > 0 & abs(heights[u] - (phylo$edge.length[i] + heights[v])) > tol )
					{ #
					  stop( 'Tree is poorly formed. Branch lengths incompatible with sample times.')
					} else if ( 0!=(heights[u] - (phylo$edge.length[i] + heights[v]) ) ){
						edgeLengthChange <- TRUE 
					}
					phylo$edge.length[i] <- max(minEdgeLength, heights[u] - heights[v] ) 
					heights[u] <- heights[v]  + phylo$edge.length[i]
				} else{
					heights[u] <- phylo$edge.length[i] + heights[v]
				}
				
				
				nextgen <- c(nextgen, u)
			}
			curgen <- unique(nextgen)
		}
	}
	phylo$heights <- heights
	phylo$maxHeight <- max(phylo$heights)
	#phylo$heights <- signif( phylo$heights, digits = floor( 1 / phylo$maxHeight /10 )  +  6 ) #
	phylo$parentheights <- sapply( 1:(n+Nnode), function(u){
		i <- which( phylo$edge[,2]== u)
		if (length(i)!=1) return( NA )
		phylo$heights[ phylo$edge[i,1] ]
	})
	
	phylo$root <- which.max( phylo$heights)
	
	ix <- sort( sampleTimes, decreasing = TRUE, index.return=TRUE)$ix
	phylo$sortedSampleHeights <- phylo$maxSampleTime - sampleTimes[ix]
	phylo$sortedSampleStates <- phylo$sampleStates[ix,] 
	
	# parents and daughters 
	phylo$parent = phylo$parents <- sapply(1:(phylo$n+phylo$Nnode), function(u) {
		i <-  which(phylo$edge[,2]==u)
		if (length(i) == 0) return (NA)
		a <- phylo$edge[i ,1]
		if (length(a) > 1) stop("Tree poorly formed; node has more than one parent.")
		a
	}) 
	phylo$daughters <- t(sapply( 1:(phylo$n+phylo$Nnode), function(a){
		uv <- phylo$edge[which(phylo$edge[,1]== a),2]
		if (length(uv)==0) uv <- c(NA, NA)
		#if (length( uv)!=2) print( uv )
		uv
	}))
	
	class(phylo) <- c("DatedTree", "phylo")
	phylo
}


sim.co.tree <- function(theta, demographic.process.model, x0, t0, sampleTimes, sampleStates=NULL, res = 1e3, integrationMethod='lsoda', finiteSizeCorrections = FALSE){
	maxSampleTime <- max(sampleTimes)
	sim.co.tree.fgy ( 
	  demographic.process.model( theta, x0, t0, maxSampleTime, res = res, integrationMethod=integrationMethod) 
	  , sampleTimes, sampleStates
	)
}
sim.co.tree.fgy <- function(tfgy,  sampleTimes, sampleStates, step_size_multiplier= NA, finiteSizeCorrections=FALSE)
{# res = 1e3, 
	# note sampleStates must be in same order as sampleTimes
	# note may return multiple trees with polytomous root
	if (is.na(step_size_multiplier)) step_size_multiplier <- .10
	times <- tfgy[[1]]
	Fs <- tfgy[[2]]
	Gs <- tfgy[[3]]
	Ys <- tfgy[[4]]
	
	m <- nrow(Fs[[1]])
	if (m < 2)  stop('Error: currently only models with at least two demes are supported')
	
	DEMES <- names( tfgy[[4]][[1]] ) 
	if (length(DEMES)!=m){
		DEMES <- as.character( 1:m )
	}
	
	if (step_size_multiplier < 0 | step_size_multiplier > 1) {
		step_size_multiplier <- 1
		warning('step_size_multiplier should be in (0, 1). This parameter has been set to 1.')
	}
	delta_times <- abs(times[2]-times[1]) 
	
	n <- length(sampleTimes)
	if (is.null( sampleStates ) ) {
		sampleStates <- matrix( 0, nrow = length(sampleTimes), ncol = m )
		sampleStates[,1] <- 1
	}
	
	#demographic model should be in order of decreasing time:
	fgyi <- 1:length(Fs)
	if (times[2] > times[1])
		fgyi <- length(Fs):1
	
	if (length(names(sampleTimes))==0){
		names(sampleTimes) <- paste(sep='_', 't', 1:length(sampleTimes))
	}
	names(sampleTimes) <- paste(sep='', 'sim', names(sampleTimes))
	maxSampleTime <- max(sampleTimes)
	ix <- sort( sampleTimes, decreasing = TRUE, index.return=TRUE)$ix
	sortedSampleHeights <- maxSampleTime - sampleTimes[ix]
	sortedSampleStates <- sampleStates[ix,] 
	sortedSampleTimes <- sampleTimes[ix]
	tlabs <- names(sampleTimes)[ix] 
	if (length(tlabs)==0){
		tlabs <- 1:n
		names(sortedSampleTimes) = names(sortedSampleHeights)  <- tlabs
	}
	
	o <- simulateTreeCpp3x0( times[fgyi],  Fs[fgyi],  Gs[fgyi],  Ys[fgyi]
	 , sortedSampleHeights #2
	 , t(sortedSampleStates)
	 , maxSampleTime
	 , m
	 , finiteSizeCorrections #TRUE #fsc
	)
	 # clean up edge, edge.length and Nnode
	o$edge <- o$edge[which(!is.na(o$edge[,1])), ]
	o$edge.length <- o$edge.length[!is.na(o$edge.length)]
	o$Nnode <- length(unique( as.vector(o$edge))) - o$n
	
	o$tip.label <- tlabs
	o$edge <- o$edge + 1
	class(o) <- 'phylo'
	
	tryCatch({
		rownames(sortedSampleStates) <- names(sortedSampleTimes )
		return(  DatedTree( read.tree(text=write.tree(o)) , sortedSampleTimes, sortedSampleStates, tol = Inf) )
	}, error = function(e) {print('Error: sim.co.tree.fgy--DatedTree'); NULL } )
}


show.demographic.process <- function(demo.model, theta, x0, t0, t1, res = 1e3, integrationMethod='lsoda', ...)
{
	tfgy <- demo.model(theta, x0, t0, t1, res = 1e3, integrationMethod=integrationMethod)
	o <- tfgy[[5]] 
	t <- o[,1]
	if ( ((ncol(o)-1)==2) & tail(colnames(o),1)=='V2'){
		# test if this is a single deme model 
		plot( t, o[, 2], type = 'l', xlab = 'Time' , ylab = colnames(o)[2], ...)
	} else{
		matplot( t, o[, 2:ncol(o)], type = 'l' , xlab = 'Time', ylab = '', ...)
		legend("bottomright", inset=.05, legend=colnames(o)[2:ncol(o)], pch=1, col=c(2,4), horiz=TRUE)
	}
}
