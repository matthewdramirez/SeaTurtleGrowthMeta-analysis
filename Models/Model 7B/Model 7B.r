# This is a Bayesian hierarchical model with multivariate normal likelihood, run in JAGS
# With hierarchical covariation in the random effects at the species level. 
library(R2jags)
library(R2OpenBUGS)
library(loo)

dat1=read.csv("DataInputJul2020.csv")

write("model {
  for (i in 1:N) {
    Y[i, 1:2] ~ dmnorm(mu[i,], Sigma.inv[,])
    LL[i]<-logdensity.mnorm(Y[i,], mu[i,],Sigma.inv[,])
    for (j in 1:2)  {
      mu[i,j]<-alpha[j]+beta[x1[i],j]+species[sp[i],j]  
      resid[i,j]<-Y[i,j]-mu[i,j]
    }
  }
  #Prior for intercept for Linf and K
  for(j in 1:2) {
    alpha[j]~dnorm(0,1.0E-6)  #loop over Linf and K
  }
  # Fixed effect priors(e.g type of sample)
  for(j in 1:2) { #loop over Linf and K
    beta[1,j]<-0  #First level of factor is reference level, set equal to zero for both Linf (alpha1) and K (alpha2)
    for(i in 2:n.beta) { #Loop over number of levels factor has 
      beta[i,j]~dnorm(0,1.0E-6)  #uninformative prior
    }}
  # Random effect priors for species
  sp.cor~dunif(-1,1)
  for(j in 1:2) {
    sp.tau[j]~dgamma(0.01,0.01)
    sp.sd[j]<-1/sqrt(sp.tau[j])
    sp.cov[j,j]<-1/sp.tau[j]
    sp.mean[j]<-0
 }
  sp.cov[1,2]<-sp.cor*sp.sd[1]*sp.sd[2]
  sp.cov[2,1]<-sp.cor*sp.sd[1]*sp.sd[2]
  sp.prec[1 : 2 , 1 : 2]  <- inverse(sp.cov[ , ])
  for(i in 1:n.sp) {
    species[i,1:2]~dmnorm(sp.mean[],sp.prec[,])
  }
  Sigma.inv[1:2, 1:2] ~ dwish(R[,], 2)
  Sigma[1:2, 1:2]<- inverse(Sigma.inv[,])
  # predicted values for each species, for reference type of sample
  for(i in 1:n.sp) {
    for(j in 1:2) {
      mean.mu[i,j]<-alpha[j]+species[i,j]
      exp.mean[i,j]<-exp(mean.mu[i,j])
    }}   
  # population intercept without log
  for(j in 1:2) {intercept[j]<-exp(alpha[j])}
}

",file="MVNsp.txt")

#Set up data to pass to JAGS
jagsdat7=list(Y=cbind(log(dat1$SCL),log(dat1$K)),x1=as.numeric(dat1$Method)
              ,N=dim(dat1)[1],R=matrix(c(2,0,0,2),2,2,byrow=TRUE),
              sp=as.numeric(dat1$Species),
              n.sp=length(unique(dat1$Species)),
              n.beta=length(unique(dat1$Method)))

# Set up initial values to pass to JAGS (one list of values for each of 2 chains)
init1=list(list(alpha=c(4,-1)),
  list(alpha=c(5,-0.5)))

# List parameters to save from MCMC
params7=c("alpha","beta","species","exp.mean",
          "sp.sd","sp.cor","intercept"
          ,"mu","resid","Sigma","LL")

res7=jags(jagsdat7,init1,params7,model.file="MVNsp.txt",
  n.chains=2,n.iter=110000,n.burnin=10000,n.thin=4)
write.csv(res7$BUGSoutput$summary,file="Model7.csv")
max(res7$BUGSoutput$summary[,"Rhat"])
min(res7$BUGSoutput$summary[,"n.eff"][res7$BUGSoutput$summary[,"n.eff"]>1])

#Make row in summary table for the run
run=7
restab=data.frame(Model=run)
restab$n.eff[1]=min(res7$BUGSoutput$summary[,"n.eff"][res7$BUGSoutput$summary[,"n.eff"]>1])
restab$Rhat[1]=round(max(res7$BUGSoutput$summary[,"Rhat"]),3)
restab$P.value[1]=NA
restab$DIC[1]=res7$BUGSoutput$DIC 
restab$pDIC[1]=res7$BUGSoutput$pD 
LLrows=paste0("LL[",1:jagsdat7$N,"]")
a=res7$BUGSoutput$sims.matrix[,LLrows]
b=waic(a)
restab$WAIC[1]=b$estimates["waic",1]
restab$pWAIC[1]=b$estimates["p_waic",2]
b=loo(a)
restab$LOOIC[1]=b$looic
restab$pLOOIC[1]=b$p_loo
restab$deviance[1]=res7$BUGSoutput$summary["deviance","mean"]
restab
write.csv(restab,paste0("waicres",run,".csv"))
pareto_k_table(b)
write.csv(pareto_k_table(b),file=paste0("paretoK",run,".csv"))


#Plot residuals
residrows=paste0("resid[",rep(1:jagsdat7$N,2),",",c(rep(1,jagsdat7$N),rep(2,jagsdat7$N)),"]")
murows=paste0("mu[",rep(1:jagsdat7$N,2),",",c(rep(1,jagsdat7$N),rep(2,jagsdat7$N)),"]")
df=data.frame(Expected=res7$BUGSoutput$summary[murows,"mean"],
              Residuals=res7$BUGSoutput$summary[residrows,"mean"],
              Variable=c(rep("Linf",jagsdat7$N),rep("K",jagsdat7$N)))
ggplot(df)+geom_point(aes(x=Expected,y=Residuals))+geom_abline(intercept=0,slope=0)+facet_wrap(~Variable,nrow=2, scales = "free")

# Look at variance parameters
sigrows=c("Sigma[1,1]","Sigma[1,2]","Sigma[2,1]","Sigma[2,2]")
a=res7$BUGSoutput$summary[sigrows,"50%"]
covmatError=matrix(a,2,2)
covmatSpecies=covmatPopulation=matrix(0,2,2)
covmatSpecies[1,1]=res7$BUGSoutput$summary["sp.sd[1]","50%"]^2
covmatSpecies[2,2]=res7$BUGSoutput$summary["sp.sd[2]","50%"]^2
covmatSpecies[1,2]=covmatSpecies[2,1]=res7$BUGSoutput$summary["sp.sd[2]","50%"]*res7$BUGSoutput$summary["sp.sd[1]","50%"]*res7$BUGSoutput$summary["sp.cor","50%"]
covmatError
covmatSpecies

