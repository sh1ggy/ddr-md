"""Folder-relative fitted transforms used by the model bundle."""
import numpy as np
from sklearn.base import BaseEstimator, RegressorMixin
from sklearn.pipeline import make_pipeline
from sklearn.svm import SVR
from scipy.spatial.distance import cdist
from kernel_models import Representation

class FolderRepresentation(Representation):
    def __init__(self,strategy='clipped',level_weight=1.,raw_weight=1.,rank_weight=1.):
        super().__init__(strategy);self.level_weight=level_weight;self.raw_weight=raw_weight;self.rank_weight=rank_weight
    def transform(self,X):
        z=super().transform(X)
        z[:,:self.raw_count_]*=self.raw_weight
        z[:,self.raw_count_:2*self.raw_count_]*=self.rank_weight
        z[:,-1]*=self.level_weight
        return z

class GroupedRepresentation(FolderRepresentation):
    def __init__(self,strategy='clipped',level_weight=10.,raw_weight=1.,rank_weight=1.,feature_weights=None):
        super().__init__(strategy,level_weight,raw_weight,rank_weight);self.feature_weights=feature_weights
    def transform(self,X):
        z=super().transform(X)
        return z if self.feature_weights is None else z*np.asarray(self.feature_weights)

class DistanceSVR(RegressorMixin,BaseEstimator):
    def __init__(self,kind='matern32',scale=2.,C=3.,epsilon=.05,level_weight=10.):
        self.kind=kind;self.scale=scale;self.C=C;self.epsilon=epsilon;self.level_weight=level_weight
    def distances(self,a,b):return cdist(a,b,metric='cityblock' if self.kind=='laplacian' else 'euclidean')
    def kernel(self,d):
        r=d/(self.distance_scale_*self.scale)
        if self.kind=='laplacian':return np.exp(-r)
        if self.kind=='matern32':
            a=np.sqrt(3)*r;return (1+a)*np.exp(-a)
        if self.kind=='cauchy':return 1/(1+r*r)
        return np.exp(-r*r)
    def fit(self,X,y,sample_weight=None):
        self.representation_=FolderRepresentation(level_weight=self.level_weight).fit(X);z=self.representation_.transform(X);d=self.distances(z,z);self.distance_scale_=float(np.median(d[np.triu_indices(len(d),1)]));self.distance_scale_=max(self.distance_scale_,1e-8);model=SVR(kernel='precomputed',C=self.C,epsilon=self.epsilon,cache_size=500).fit(self.kernel(d),y,sample_weight=sample_weight);self.supports_=z[model.support_];self.coefficients_=model.dual_coef_[0];self.intercept_=float(model.intercept_[0]);return self
    def predict(self,X):
        z=self.representation_.transform(X);return self.kernel(self.distances(z,self.supports_))@self.coefficients_+self.intercept_
