"""Frozen fitted feature transform; module name is part of the model format."""
import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin
from sklearn.preprocessing import StandardScaler, QuantileTransformer

class Representation(BaseEstimator,TransformerMixin):
    def __init__(self,strategy='standard',physical_weight=1.):
        self.strategy=strategy;self.physical_weight=physical_weight
    def fit(self,X,y=None):
        self.raw_count_=(X.shape[1]-1)//2
        if self.strategy=='ranks':self.transformer_=None
        elif self.strategy=='quantile':self.transformer_=QuantileTransformer(n_quantiles=min(200,len(X)),output_distribution='uniform',random_state=17).fit(X)
        elif self.strategy=='clipped':self.transformer_=StandardScaler().fit(X)
        else:self.transformer_=StandardScaler().fit(X)
        return self
    def transform(self,X):
        if self.strategy=='ranks':return X[:,self.raw_count_:2*self.raw_count_]
        z=self.transformer_.transform(X)
        if self.strategy=='clipped':z=np.clip(z,-3,3)
        return z
