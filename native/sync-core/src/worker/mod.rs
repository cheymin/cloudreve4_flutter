mod pool;
mod worker_impl;

pub use pool::WorkerPool;
#[cfg(feature = "windows-cfapi")]
pub use worker_impl::PlaceholderCreator;
pub use worker_impl::Worker;
